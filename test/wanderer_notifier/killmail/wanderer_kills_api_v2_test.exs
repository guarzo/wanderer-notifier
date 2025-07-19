defmodule WandererNotifier.Killmail.WandererKillsAPIV2Test do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.WandererKillsAPIV2

  setup :verify_on_exit!

  describe "WandererKillsAPIV2 basic functionality" do
    test "get_killmail uses new base client" do
      killmail_id = 12_345

      expected_response = %{
        "killmail_id" => killmail_id,
        "killmail_time" => "2023-01-01T00:00:00Z",
        "victim" => %{
          "character_id" => 98_765,
          "ship_type_id" => 587
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn url, headers, opts ->
        assert url == "http://host.docker.internal:4004/api/v1/kills/#{killmail_id}"
        assert {"Content-Type", "application/json"} in headers
        assert {"Accept", "application/json"} in headers
        assert {"User-Agent", "WandererNotifier/1.0"} in headers
        assert opts[:timeout] == 10_000
        assert opts[:retry_options][:max_attempts] == 3
        assert opts[:rate_limit_options][:requests_per_second] == 10

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = WandererKillsAPIV2.get_killmail(killmail_id)

      assert {:ok, transformed} = result
      assert transformed["killmail_id"] == killmail_id
      assert transformed["enriched"] == true
      assert transformed["victim"]["character_name"] == nil
    end

    test "fetch_systems_killmails handles multi-system response" do
      system_ids = [30_000_142, 30_000_143]

      expected_response = %{
        "systems" => %{
          "30000142" => [
            %{"killmail_id" => 1, "victim" => %{"character_id" => 123}},
            %{"killmail_id" => 2, "victim" => %{"character_id" => 456}}
          ],
          "30000143" => [
            %{"killmail_id" => 3, "victim" => %{"character_id" => 789}}
          ]
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
        assert url =~ "/api/v1/kills/systems?"
        assert url =~ "system_ids=30000142%2C30000143"
        assert url =~ "since_hours=24"
        assert url =~ "limit_per_system=50"

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = WandererKillsAPIV2.fetch_systems_killmails(system_ids)

      assert {:ok, systems_data} = result
      assert length(systems_data[30_000_142]) == 2
      assert length(systems_data[30_000_143]) == 1
      assert Enum.all?(systems_data[30_000_142], fn kill -> kill["enriched"] == true end)
    end

    test "subscribe_to_killmails sends POST request" do
      subscriber_id = "test_subscriber"
      system_ids = [30_000_142]
      callback_url = "https://example.com/webhook"

      expect(WandererNotifier.HTTPMock, :post, fn url, body, headers, _opts ->
        assert url == "http://host.docker.internal:4004/api/v1/subscriptions"
        assert {"Content-Type", "application/json"} in headers

        decoded_body = Jason.decode!(body)
        assert decoded_body["subscriber_id"] == subscriber_id
        assert decoded_body["system_ids"] == system_ids
        assert decoded_body["callback_url"] == callback_url

        {:ok, %{status_code: 201, body: %{"subscription_id" => "sub_123"}}}
      end)

      result = WandererKillsAPIV2.subscribe_to_killmails(subscriber_id, system_ids, callback_url)
      assert {:ok, "sub_123"} = result
    end

    test "health_check uses shorter timeout" do
      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, opts ->
        assert url == "http://host.docker.internal:4004/api/v1/health"
        assert opts[:timeout] == 5_000

        {:ok, %{status_code: 200, body: %{"status" => "healthy"}}}
      end)

      result = WandererKillsAPIV2.health_check()
      assert {:ok, %{"status" => "healthy"}} = result
    end

    test "handles errors with enhanced error formatting" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 429, body: "Rate limit exceeded"}}
      end)

      result = WandererKillsAPIV2.get_killmail(12_345)
      assert {:error, %{type: :rate_limit, message: message}} = result
      assert message =~ "get_killmail failed"
    end

    test "handles network errors" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      result = WandererKillsAPIV2.health_check()
      assert {:error, :timeout} = result
    end
  end

  describe "WandererKillsAPIV2 configuration" do
    test "uses correct base configuration" do
      assert WandererKillsAPIV2.base_url() == "http://host.docker.internal:4004"
      assert WandererKillsAPIV2.default_timeout() == 10_000
      assert WandererKillsAPIV2.default_recv_timeout() == 10_000
      assert WandererKillsAPIV2.service_name() == "wanderer_kills"
    end
  end

  describe "WandererKillsAPIV2 transform functions" do
    test "handles server errors with proper categorization" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 503, body: "Service Unavailable"}}
      end)

      result = WandererKillsAPIV2.get_killmail(123)
      assert {:error, %{type: :server_error, message: message}} = result
      assert message =~ "get_killmail failed"
    end

    test "handles 404 errors correctly" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      result = WandererKillsAPIV2.get_killmail(999)
      assert {:error, %{type: :not_found, message: message}} = result
      assert message =~ "get_killmail failed"
    end
  end

  describe "bulk_load_system_kills" do
    test "processes systems in chunks" do
      # More than 10 to test chunking
      system_ids = Enum.to_list(1..25)

      # Expect multiple calls for chunks
      expect(WandererNotifier.HTTPMock, :get, 3, fn url, _headers, _opts ->
        assert url =~ "/api/v1/kills/systems?"
        {:ok, %{status_code: 200, body: %{"systems" => %{}}}}
      end)

      result = WandererKillsAPIV2.bulk_load_system_kills(system_ids, 24)
      assert {:ok, %{loaded: 0, errors: []}} = result
    end
  end
end
