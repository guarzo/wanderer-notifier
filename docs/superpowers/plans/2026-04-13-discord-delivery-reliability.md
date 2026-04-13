# Discord Delivery Reliability Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix silent kill notification loss by adding retry logic, health tracking, and accurate failure counting to the HttpClient Discord send path.

**Architecture:** The pipeline always fans out via MapRegistry, producing a MapConfig even in single-map mode. This routes all sends through `DiscordHttpClient` (direct REST), which currently has no retries and no health tracking. The Nostrum path with retries/health is dead code. We add retry-with-backoff at the HttpClient level (transport errors only — safe to retry because the request never reached Discord), wire ConnectionHealth calls into the `discord_notifier.ex` result handler, and fix the counter gap where `record_failed_killmail` silently swallowed failures without incrementing health counters.

**Tech Stack:** Elixir/OTP, Mox for testing, ConnectionHealth GenServer

---

### Task 1: Add retry with backoff to HttpClient for transport errors

**Files:**
- Modify: `lib/wanderer_notifier/domains/notifications/discord/http_client.ex:70-112`
- Create: `test/wanderer_notifier/domains/notifications/discord/http_client_test.exs`

Transport errors (TCP timeout, connection refused) mean the request never reached Discord — safe to retry without risking duplicate messages. HTTP-level errors (4xx, 5xx responses) are NOT retried here because the message may have been processed server-side. Rate limits (429) are already handled by the DynamicRateLimiter middleware.

- [ ] **Step 1: Write failing tests for retry behavior**

Create `test/wanderer_notifier/domains/notifications/discord/http_client_test.exs`:

```elixir
defmodule WandererNotifier.Domains.Notifications.Discord.HttpClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias WandererNotifier.Domains.Notifications.Discord.HttpClient

  setup :verify_on_exit!

  setup do
    # Use the HTTP mock for all tests
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.HTTPMock)

    on_exit(fn ->
      Application.delete_env(:wanderer_notifier, :http_client)
    end)

    :ok
  end

  describe "send_embed/3 retry on transport errors" do
    test "succeeds on first attempt without retry" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: %{}}}
      end)

      assert {:ok, :sent} = HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "retries on transport error and succeeds" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: %{}}}
      end)

      assert {:ok, :sent} = HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "returns error after exhausting retries on transport errors" do
      WandererNotifier.HTTPMock
      |> expect(:request, 3, fn :post, _url, _body, _headers, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, %Req.TransportError{reason: :timeout}} =
               HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "does not retry on HTTP-level errors" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 500, body: %{"message" => "Internal Server Error"}}}
      end)

      assert {:error, {:discord_api_error, 500}} =
               HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "does not retry on rate limit responses" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 429, body: %{"retry_after" => 1.5}}}
      end)

      assert {:error, {:rate_limited, 1.5}} =
               HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/wanderer_notifier/domains/notifications/discord/http_client_test.exs --trace`
Expected: "retries on transport error and succeeds" and "returns error after exhausting retries" should fail (no retry logic exists yet). Others may pass or fail depending on mock wiring.

- [ ] **Step 3: Implement retry logic in HttpClient**

In `lib/wanderer_notifier/domains/notifications/discord/http_client.ex`, add retry constants and replace `send_message_payload/4` with a version that retries on transport errors:

Add after the `@discord_embed_key_map` line (~line 25):

```elixir
@max_retries 2
@initial_retry_delay_ms 500
```

Replace the existing `send_message_payload/4` function (lines 70-112) with:

```elixir
defp send_message_payload(bot_token, channel_id, payload, caller_opts) do
  url = "#{@discord_api_base}/channels/#{channel_id}/messages"

  headers = [
    {"Authorization", "Bot #{bot_token}"},
    {"Content-Type", "application/json"}
  ]

  defaults = [service: :discord, rate_limit: [bucket_key: token_bucket_key(bot_token)]]
  opts = Keyword.merge(defaults, caller_opts)

  do_send_with_retry(url, payload, headers, opts, channel_id, _attempt = 0)
end

defp do_send_with_retry(url, payload, headers, opts, channel_id, attempt) do
  case Http.request(:post, url, payload, headers, opts) do
    {:ok, %{status_code: status}} when status in 200..299 ->
      {:ok, :sent}

    {:ok, %{status_code: 429, body: body}} ->
      retry_after = extract_retry_after(body)

      Logger.warning("Discord rate limited",
        channel_id: channel_id,
        retry_after: retry_after
      )

      {:error, {:rate_limited, retry_after}}

    {:ok, %{status_code: status, body: body}} ->
      Logger.error("Discord API error",
        status: status,
        channel_id: channel_id,
        body: inspect(body)
      )

      {:error, {:discord_api_error, status}}

    {:error, reason} when attempt < @max_retries ->
      delay = retry_delay(attempt)

      Logger.warning("Discord transport error, retrying",
        channel_id: channel_id,
        error: inspect(reason),
        attempt: attempt + 1,
        max_retries: @max_retries,
        retry_in_ms: delay
      )

      Process.sleep(delay)
      do_send_with_retry(url, payload, headers, opts, channel_id, attempt + 1)

    {:error, reason} ->
      Logger.error("Discord request failed after #{@max_retries} retries",
        channel_id: channel_id,
        error: inspect(reason)
      )

      {:error, reason}
  end
end

defp retry_delay(attempt) do
  trunc(@initial_retry_delay_ms * :math.pow(2, attempt))
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/wanderer_notifier/domains/notifications/discord/http_client_test.exs --trace`
Expected: All 5 tests pass.

- [ ] **Step 5: Run full quality gates**

Run: `make compile && mix credo --strict`
Expected: No errors, no credo issues.

- [ ] **Step 6: Commit**

```bash
git add lib/wanderer_notifier/domains/notifications/discord/http_client.ex test/wanderer_notifier/domains/notifications/discord/http_client_test.exs
git commit -m "fix: add retry with backoff to Discord HttpClient for transport errors

Transport-level errors (TCP timeout, connection refused) are safe to retry
because the request never reached Discord. Retries up to 2 times with
exponential backoff (500ms, 1000ms). HTTP-level errors and rate limits
are not retried to avoid duplicate messages."
```

---

### Task 2: Add ConnectionHealth tracking to HttpClient send path

**Files:**
- Modify: `lib/wanderer_notifier/discord_notifier.ex:584-601`

The `send_to_discord_for_map` result handler logs success/failure but never calls `ConnectionHealth.record_success()` or `ConnectionHealth.record_failure()`. The Nostrum path does this in `neo_client.ex:347-378`, but the HttpClient path bypasses it entirely.

- [ ] **Step 1: Add health tracking calls to send_to_discord_for_map**

In `lib/wanderer_notifier/discord_notifier.ex`, modify the `case result do` block in `send_to_discord_for_map/3` (starting at line 584):

Replace:
```elixir
    case result do
      {:ok, :sent} ->
        Logger.info("Discord notification sent for map #{mc.slug}",
          channel: channel_id,
          map_slug: mc.slug
        )

        {:ok, :sent}

      {:error, reason} ->
        Logger.error("Discord notification failed for map #{mc.slug}",
          channel: channel_id,
          map_slug: mc.slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
```

With:
```elixir
    case result do
      {:ok, :sent} ->
        ConnectionHealth.record_success()

        Logger.info("Discord notification sent for map #{mc.slug}",
          channel: channel_id,
          map_slug: mc.slug
        )

        {:ok, :sent}

      {:error, reason} ->
        ConnectionHealth.record_failure(reason)

        Logger.error("Discord notification failed for map #{mc.slug}",
          channel: channel_id,
          map_slug: mc.slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
```

- [ ] **Step 2: Add the ConnectionHealth alias if not already present**

Check the top of `discord_notifier.ex` for existing aliases. The `record_failed_kill/2` function at line 301 already uses `alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth` inline. Move it to the module-level alias block to avoid repetition. If a module-level alias already exists, skip this step.

Add to the alias block near the top of the module:
```elixir
alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth
```

Then remove the inline alias from `record_failed_kill/2` at line 301.

- [ ] **Step 3: Run quality gates**

Run: `make compile && make test && mix credo --strict`
Expected: Compilation succeeds, all tests pass, no credo issues.

- [ ] **Step 4: Commit**

```bash
git add lib/wanderer_notifier/discord_notifier.ex
git commit -m "fix: add ConnectionHealth tracking to HttpClient Discord send path

The multi-map send path (send_to_discord_for_map) now records success
and failure with ConnectionHealth, making health metrics accurate for
the HttpClient path. Previously only the unused Nostrum path tracked
health, leaving total_success=0 and total_failures=0 permanently."
```

---

### Task 3: Fix record_failed_killmail to increment failure counters

**Files:**
- Modify: `lib/wanderer_notifier/domains/notifications/discord/connection_health.ex:240-248`
- Create: `test/wanderer_notifier/domains/notifications/discord/connection_health_test.exs`

Currently `record_failed_killmail/2` only adds to the `failed_kills` list without incrementing `total_failures` or `consecutive_failures`. This was designed assuming NeoClient handles the counter — but in the HttpClient path, NeoClient never touches ConnectionHealth. Now that Task 2 adds `record_failure` at the `discord_notifier` level, `record_failed_killmail` should stay as list-only to avoid double-counting. However, the comment on line 241 is misleading and should be updated for clarity.

**Wait — re-evaluation:** With Task 2 in place, `record_failure` is called for send failures, and `record_failed_killmail` is called separately in `dispatch_to_map_channels` at line 539 for partial failures. These are complementary: `record_failure` tracks per-channel-send health, `record_failed_killmail` tracks per-kill outcomes. The counter gap is now fixed by Task 2. What remains is updating the comment and ensuring `dispatch_to_map_channels` doesn't double-count.

- [ ] **Step 1: Write a test for ConnectionHealth counter behavior**

Create `test/wanderer_notifier/domains/notifications/discord/connection_health_test.exs`:

```elixir
defmodule WandererNotifier.Domains.Notifications.Discord.ConnectionHealthTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth

  setup do
    # Stop existing instance if running, start fresh for each test
    case GenServer.whereis(ConnectionHealth) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    {:ok, _pid} = ConnectionHealth.start_link([])

    on_exit(fn ->
      case GenServer.whereis(ConnectionHealth) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal)
      end
    end)

    :ok
  end

  describe "record_success/0" do
    test "increments total_successes counter" do
      ConnectionHealth.record_success()
      ConnectionHealth.record_success()
      # Give GenServer time to process casts
      Process.sleep(50)

      {:ok, status} = ConnectionHealth.get_health_status()
      assert status.total_successes == 2
    end
  end

  describe "record_failure/2" do
    test "increments total_failures counter and adds to failed_kills" do
      ConnectionHealth.record_failure(:timeout, "kill-123")
      Process.sleep(50)

      {:ok, status} = ConnectionHealth.get_health_status()
      assert status.total_failures == 1
      assert length(status.failed_kills) == 1
      assert hd(status.failed_kills).killmail_id == "kill-123"
    end
  end

  describe "record_failed_killmail/2" do
    test "adds to failed_kills list without incrementing counters" do
      ConnectionHealth.record_failed_killmail("kill-456", :partial_failure)
      Process.sleep(50)

      {:ok, status} = ConnectionHealth.get_health_status()
      assert status.total_failures == 0
      assert status.total_successes == 0
      assert length(status.failed_kills) == 1
      assert hd(status.failed_kills).killmail_id == "kill-456"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `mix test test/wanderer_notifier/domains/notifications/discord/connection_health_test.exs --trace`
Expected: All 3 tests pass (validating existing behavior is correct).

- [ ] **Step 3: Update the misleading comment in connection_health.ex**

In `lib/wanderer_notifier/domains/notifications/discord/connection_health.ex`, update the comment at line 241:

Replace:
```elixir
  def handle_cast({:record_failed_killmail, killmail_id, reason}, state) do
    # Only add to failed_kills list, don't affect counters (NeoClient handles those)
    new_state = %{
```

With:
```elixir
  def handle_cast({:record_failed_killmail, killmail_id, reason}, state) do
    # Only add to failed_kills list, don't affect counters.
    # Health counters are recorded separately via record_success/record_failure
    # at the send site (discord_notifier.ex send_to_discord_for_map).
    new_state = %{
```

- [ ] **Step 4: Update the comment in discord_notifier.ex record_failed_kill**

In `lib/wanderer_notifier/discord_notifier.ex`, update the comment at line 303:

Replace:
```elixir
    # Use record_failed_killmail to add to the failed kills list without affecting counters
    # (NeoClient already records the failure/timeout for health metrics)
```

With:
```elixir
    # Use record_failed_killmail to add to the failed kills list without affecting counters.
    # Health counters (total_successes, total_failures) are tracked per-channel-send
    # in send_to_discord_for_map via ConnectionHealth.record_success/record_failure.
```

- [ ] **Step 5: Run full quality gates**

Run: `make compile && make test && mix credo --strict`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/wanderer_notifier/domains/notifications/discord/connection_health.ex lib/wanderer_notifier/discord_notifier.ex test/wanderer_notifier/domains/notifications/discord/connection_health_test.exs
git commit -m "fix: clarify health counter responsibility and add ConnectionHealth tests

Updates misleading comments that referenced NeoClient as the counter
owner. With the HttpClient path now recording health directly in
send_to_discord_for_map, the comments accurately reflect the actual
counter flow. Adds tests validating counter behavior."
```

---

### Task 4: Integration verification

**Files:** None (verification only)

- [ ] **Step 1: Run full quality gate script**

Run: `./scripts/validate-quality.sh`
Expected: All 4 gates pass (compile, test, credo --strict, dialyzer).

- [ ] **Step 2: Verify health log format still correct**

Check that the health status log at `connection_health.ex:649-657` will now show non-zero `total_success` and `total_timeout` values after successful/failed sends through the HttpClient path. No code change needed — this is a manual review step.

- [ ] **Step 3: Verify retry logging will be visible**

Confirm the new retry warning log in `http_client.ex` will appear in production logs with the same structured metadata format used elsewhere. No code change needed.
