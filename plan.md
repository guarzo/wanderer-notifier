# Refactoring Plan

## 1. Refactor Killmail Pipeline & Error Handling ✅

### Remove unused flags ✅

Search for `skip_tracking_check` and `skip_notification_check` in `lib/wanderer_notifier/killmail/pipeline.ex`.

Delete their definitions and all callers; run `grep -R "skip_notification_check" -n lib/` to be sure nothing breaks.

### Flatten with with/1 ✅

Rewrite `process_killmail/2` from nested clauses into a single with chain. For example:

```elixir
def process_killmail(data, ctx) do
  with {:ok, km}       <- create_killmail(data, ctx),
       {:ok, enriched} <- Enrichment.enrich_killmail(enriched),
       true            <- NotificationChecker.should_notify?(enriched) do
    Notification.send(enriched)
  else
    false           -> {:ok, :skipped}
    {:error, reason} -> {:error, reason}
  end
end
```

Ensure you still call `Stats.increment/1` before or after as needed.

### Narrow your rescue ✅

Replace any `rescue e -> {:error, Exception.message(e)}` with explicit catches:

```elixir
rescue
  e in ESIService.TimeoutError -> {:error, :timeout}
  e in ESIService.ApiError     -> {:error, e.reason}
```

Remove any catch-all clauses so unexpected errors bubble up.

### Add tests for each branch ⚠️

In `test/wanderer_notifier/killmail/pipeline_test.exs`, write cases for:

- successful send
- enrichment error
- no-notify branch (returning `{:ok, :skipped}`)
- each explicit exception type

## 2. DRY Caching & Key Generation ⚠️

### Centralize TTLs ✅

In `lib/wanderer_notifier/config.ex`, add functions:

```elixir
def notification_dedup_ttl, do: Application.get_env(:wanderer_notifier, :dedup_ttl, 60)
def static_info_ttl,        do: Application.get_env(:wanderer_notifier, :static_info_ttl, 3600)
```

Replace all hard-coded TTL literals with calls to these.

### Generate keys via macro ❌

In `lib/wanderer_notifier/cache/keys.ex`, replace individual functions with:

```elixir
defmacro defkey(name, parts) do
  quote do
    def unquote(name)(unquote_splicing(Enum.map(parts, &Macro.var(&1, nil))), extra \\ nil) do
      ([unquote_splicing(parts)] ++ [to_string(unquote(Macro.var(Enum.at(parts, -1), nil))), extra])
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")
    end
  end
end

# then at module top:
defkey :killmail,    [:esi, :killmail_id]
defkey :corporation, [:esi, :corporation_id]
# …etc.
```


### Update callers & tests ✅

Run `grep -R "Cache.Keys." -n lib/` and adjust to new signatures.

Add a few unit tests in `test/cache/keys_test.exs` asserting correct string outputs.

## 3. Standardize Behaviours & Dependency Injection ✅

### Unify behaviour names ✅

Choose one suffix (e.g. …Behaviour). Rename files accordingly:

```bash
lib/wanderer_notifier/http_client_behaviour.ex
lib/wanderer_notifier/zkill_client_behaviour.ex
lib/wanderer_notifier/cache_behaviour.ex
lib/wanderer_notifier/config_behaviour.ex
```

Delete duplicates in `test/…` and point mocks at the single definitions.

### Update implementations ✅

In each module (e.g. `WandererNotifier.ZKillClient`), change `@behaviour OldName` to `@behaviour ZKillClientBehaviour`.

Fix any callback mismatches.

### Configure via application env ✅

In `config/config.exs`:

```elixir
config :wanderer_notifier,
  http_client: WandererNotifier.HttpClient,
  zkill_client:  WandererNotifier.ZKillClient,
  cache_repo:    WandererNotifier.Cache
```

Wherever you call `Application.get_env(:wanderer_notifier, :http_client)`, leave as is but be sure it now points to the right module.

### Adjust tests ✅

In `test/support/mocks.ex`, set up Mox:

```elixir
Mox.defmock(HttpClientMock, for: HttpClientBehaviour)
Application.put_env(:wanderer_notifier, :http_client, HttpClientMock)
```

Remove any ad-hoc `put_env` calls sprinkled through individual tests.

## 4. Enhance Logging & Observability ⚠️

### Audit all AppLogger calls ⚠️

Search for `AppLogger.` in `lib/`. Ensure each call includes identifying metadata, e.g.:

```elixir
AppLogger.api_debug("Fetched killmail", kill_id: km.id, module: __MODULE__)
```

### Define a logging convention doc ❌

Create `docs/logging.md` with rules:

- Use …\_info/2 for normal ops
- …\_error/2 for failures (include error: reason)
- Always attach id: and context: keys

### Wrap dev-only loops ✅

In any module that logs in a tight loop (e.g. monitoring), guard with:

```elixir
if Config.dev_mode?() do
  # loop …
end
```

Add `dev_mode?/0` in your config module:

```elixir
def dev_mode?, do: Application.get_env(:wanderer_notifier, :dev_mode, false)
```

### Hook up a metrics reporter ❌

If you haven't already, integrate Telemetry:

```elixir
:telemetry.attach("kill-pipeline-end", [:wanderer, :killmail, :processed], &MyReporter.handle_event/4, nil)
```

Emit events at key points in `process_killmail/2`.

## 5. Improve Coding Style & Readability ⚠️

### Replace cond with guards ⚠️

Find multi-branch `cond do` in `lib/`. For simple cases, refactor into separate heads:

```elixir
# before
def classify(map) do
  cond do
    Map.has_key?(map, "zkb") -> :killmail
    Map.has_key?(map, "system_id") -> :system
    true -> :unknown
  end
end

# after
def classify(map) when is_map(map) and Map.has_key?(map, "zkb"), do: :killmail
def classify(map) when is_map(map) and Map.has_key?(map, "system_id"), do: :system
def classify(_), do: :unknown
```

### Audit @spec and @doc ⚠️

In each `lib/**/*.ex`, ensure every public function has `@spec` and `@doc`.

If missing, add stubs:

```elixir
@doc "Fetches a killmail by ID and context"
@spec create_killmail(map(), Context.t()) :: {:ok, Killmail.t()} | {:error, term()}
```

### Standardize aliases ⚠️

At the top of each file, group aliases:

```elixir
alias WandererNotifier.Killmail.{Enrichment, Notification}
alias WandererNotifier.ESI.Service
```

No more more-than-two-deep nesting without an alias.

### Run mix format & Credo ✅

Apply `mix format --check-formatted`; fix any issues.

Re-enable strict Credo checks for complexity and unused code in `mix.exs`, then iterate until your score is green.
