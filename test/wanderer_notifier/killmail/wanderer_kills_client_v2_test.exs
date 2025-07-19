defmodule WandererNotifier.Killmail.WandererKillsClientV2Test do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.WandererKillsClientV2

  setup :verify_on_exit!

  describe "WandererKillsClientV2 basic functionality" do
    test "get_system_kills returns kills data" do
      system_id = 30_000_142
      limit = 5
      since_hours = 168

      expected_response = [
        %{
          "killmail_id" => 12345,
          "killmail_time" => "2023-01-01T00:00:00Z",
          "victim" => %{
            "character_id" => 98765,
            "ship_type_id" => 587
          }
        }
      ]

      expect(WandererNotifier.HTTPMock, :get, fn url, headers, opts ->
        assert url ==
                 "http://host.docker.internal:4004/api/v1/kills/system/#{system_id}?limit=#{limit}&since_hours=#{since_hours}"

        assert {"Content-Type", "application/json"} in headers
        assert {"Accept", "application/json"} in headers
        assert {"User-Agent", "WandererNotifier/1.0"} in headers
        assert opts[:timeout] == 10_000
        assert opts[:retry_options][:max_attempts] == 3
        assert opts[:rate_limit_options][:requests_per_second] == 10

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = WandererKillsClientV2.get_system_kills(system_id, limit, since_hours)
      assert {:ok, kills} = result
      assert length(kills) == 1
      assert List.first(kills)["killmail_id"] == 12345
    end

    test "get_character_kills returns character kills data" do
      character_id = 98765
      limit = 10
      since_hours = 168

      expected_response = %{
        "kills" => [
          %{
            "killmail_id" => 54321,
            "killmail_time" => "2023-01-01T01:00:00Z",
            "victim" => %{
              "character_id" => character_id,
              "ship_type_id" => 587
            }
          }
        ]
      }

      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
        assert url ==
                 "http://host.docker.internal:4004/api/v1/kills/character/#{character_id}?limit=#{limit}&since_hours=#{since_hours}"

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = WandererKillsClientV2.get_character_kills(character_id, limit, since_hours)
      assert {:ok, kills} = result
      assert length(kills) == 1
      assert List.first(kills)["killmail_id"] == 54321
    end

    test "get_recent_kills returns recent kills data" do
      limit = 10
      since_hours = 168

      expected_response = [
        %{
          "killmail_id" => 99999,
          "killmail_time" => "2023-01-01T02:00:00Z"
        },
        %{
          "killmail_id" => 88888,
          "killmail_time" => "2023-01-01T01:30:00Z"
        }
      ]

      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
        assert url ==
                 "http://host.docker.internal:4004/api/v1/kills/recent?limit=#{limit}&since_hours=#{since_hours}"

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = WandererKillsClientV2.get_recent_kills(limit, since_hours)
      assert {:ok, kills} = result
      assert length(kills) == 2
      assert Enum.any?(kills, fn kill -> kill["killmail_id"] == 99999 end)
      assert Enum.any?(kills, fn kill -> kill["killmail_id"] == 88888 end)
    end

    test "uses default parameters correctly" do
      system_id = 30_000_142

      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
        assert url =~ "limit=5"
        assert url =~ "since_hours=168"
        {:ok, %{status_code: 200, body: []}}
      end)

      result = WandererKillsClientV2.get_system_kills(system_id)
      assert {:ok, []} = result
    end

    test "handles HTTP errors gracefully" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 500, body: "Internal Server Error"}}
      end)

      result = WandererKillsClientV2.get_system_kills(30_000_142)
      assert {:error, _reason} = result
    end

    test "handles network timeouts" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      result = WandererKillsClientV2.get_character_kills(98765)
      assert {:error, :timeout} = result
    end

    test "handles unexpected response format gracefully" do
      unexpected_response = %{
        "unexpected_field" => "unexpected_value",
        "not_kills" => "not_an_array"
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: unexpected_response}}
      end)

      result = WandererKillsClientV2.get_recent_kills()
      # Should return empty list for unexpected format
      assert {:ok, []} = result
    end
  end

  describe "WandererKillsClientV2 configuration" do
    test "uses correct base configuration" do
      assert WandererKillsClientV2.base_url() == "http://host.docker.internal:4004"
      assert WandererKillsClientV2.default_timeout() == 10_000
      assert WandererKillsClientV2.default_recv_timeout() == 10_000
      assert WandererKillsClientV2.service_name() == "wanderer_kills_client"
    end
  end

  describe "WandererKillsClientV2 response handling" do
    test "handles response with kills array directly" do
      kills_array = [
        %{"killmail_id" => 1, "victim" => %{}},
        %{"killmail_id" => 2, "victim" => %{}}
      ]

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: kills_array}}
      end)

      result = WandererKillsClientV2.get_system_kills(30_000_142)
      assert {:ok, kills} = result
      assert length(kills) == 2
    end

    test "handles response with kills nested in object" do
      nested_response = %{
        "kills" => [
          %{"killmail_id" => 3, "victim" => %{}},
          %{"killmail_id" => 4, "victim" => %{}}
        ],
        "metadata" => %{"total" => 2}
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: nested_response}}
      end)

      result = WandererKillsClientV2.get_character_kills(98765)
      assert {:ok, kills} = result
      assert length(kills) == 2
    end

    test "handles JSON decode errors" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: "invalid json"}}
      end)

      result = WandererKillsClientV2.get_recent_kills()
      assert {:error, {:json_decode_error, _}} = result
    end
  end

  describe "WandererKillsClientV2 rate limiting and retries" do
    test "configures proper retry options" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, opts ->
        retry_opts = opts[:retry_options]
        assert retry_opts[:max_attempts] == 3
        assert retry_opts[:retryable_errors] == [:timeout, :connect_timeout, :econnrefused]
        assert 429 in retry_opts[:retryable_status_codes]
        assert 500 in retry_opts[:retryable_status_codes]
        assert retry_opts[:context] == "WandererKills request"

        {:ok, %{status_code: 200, body: []}}
      end)

      WandererKillsClientV2.get_system_kills(30_000_142)
    end

    test "configures proper rate limit options" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, opts ->
        rate_limit_opts = opts[:rate_limit_options]
        assert rate_limit_opts[:per_host] == true
        assert rate_limit_opts[:requests_per_second] == 10
        assert rate_limit_opts[:burst_capacity] == 20

        {:ok, %{status_code: 200, body: []}}
      end)

      WandererKillsClientV2.get_character_kills(98765)
    end
  end
end
