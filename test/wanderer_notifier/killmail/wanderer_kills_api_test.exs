defmodule WandererNotifier.Killmail.WandererKillsAPITest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.HTTPMock, as: HttpClientMock
  alias WandererNotifier.Domains.Killmail.WandererKillsAPI

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # Capture original value to restore after test
    original_http_client = Application.get_env(:wanderer_notifier, :http_client)

    # Set up the HTTP client mock
    Application.put_env(:wanderer_notifier, :http_client, HttpClientMock)

    on_exit(fn ->
      # Restore original value
      if original_http_client do
        Application.put_env(:wanderer_notifier, :http_client, original_http_client)
      else
        Application.delete_env(:wanderer_notifier, :http_client)
      end
    end)

    :ok
  end

  describe "fetch_system_killmails/3" do
    test "returns transformed killmails with enriched flag" do
      system_id = 30_000_142

      expected_response = %{
        "kills" => [
          %{
            "killmail_id" => 12_345,
            "kill_time" => "2024-01-01T00:00:00Z",
            "system_id" => system_id,
            "victim" => %{
              "character_id" => 95_123_456,
              "ship_type_id" => 587
            },
            "attackers" => [
              %{
                "character_id" => 95_654_321,
                "final_blow" => true,
                "ship_type_id" => 11_567
              }
            ]
          }
        ]
      }

      HttpClientMock
      |> expect(:request, fn :get, _url, nil, _headers, _opts ->
        {:ok, %{status_code: 200, body: expected_response}}
      end)

      assert {:ok, kills} = WandererKillsAPI.fetch_system_killmails(system_id, 24, 100)
      assert length(kills) == 1

      [kill | _] = kills
      assert kill["enriched"] == true
      assert kill["killmail_id"] == 12_345
      assert is_map(kill["victim"])
      assert is_list(kill["attackers"])
    end

    test "returns proper error response on failure" do
      system_id = 30_000_142

      HttpClientMock
      |> expect(:request, fn :get, _url, nil, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, %{type: :network_error, message: message}} =
               WandererKillsAPI.fetch_system_killmails(system_id)

      assert message =~ ":timeout"
    end
  end

  describe "fetch_systems_killmails/3" do
    test "returns map of system_id to killmails" do
      system_ids = [30_000_142, 30_000_143]

      expected_response = %{
        "systems" => %{
          "30000142" => [
            %{
              "killmail_id" => 12_345,
              "system_id" => 30_000_142,
              "victim" => %{},
              "attackers" => []
            }
          ],
          "30000143" => [
            %{
              "killmail_id" => 67_890,
              "system_id" => 30_000_143,
              "victim" => %{},
              "attackers" => []
            }
          ]
        }
      }

      HttpClientMock
      |> expect(:request, fn :post, _url, body, _headers, _opts ->
        parsed_body = Jason.decode!(body)
        assert parsed_body["system_ids"] == [30_000_142, 30_000_143]
        {:ok, %{status_code: 200, body: expected_response}}
      end)

      assert {:ok, result} = WandererKillsAPI.fetch_systems_killmails(system_ids, 24, 50)
      assert Map.has_key?(result, 30_000_142)
      assert Map.has_key?(result, 30_000_143)
      assert length(result[30_000_142]) == 1
      assert length(result[30_000_143]) == 1
    end

    test "handles string system_ids in response" do
      system_ids = [30_000_142]

      expected_response = %{
        "systems" => %{
          "30000142" => [
            %{"killmail_id" => 12_345}
          ]
        }
      }

      HttpClientMock
      |> expect(:request, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: expected_response}}
      end)

      assert {:ok, result} = WandererKillsAPI.fetch_systems_killmails(system_ids)
      assert Map.has_key?(result, 30_000_142)
    end
  end

  describe "get_killmail/1" do
    test "fetches single killmail by ID" do
      killmail_id = 12_345

      expected_killmail = %{
        "killmail_id" => killmail_id,
        "victim" => %{"character_id" => 95_123_456},
        "attackers" => []
      }

      HttpClientMock
      |> expect(:request, fn :get, url, nil, _headers, _opts ->
        assert url =~ "/api/v1/killmail/#{killmail_id}"
        {:ok, %{status_code: 200, body: expected_killmail}}
      end)

      assert {:ok, kill} = WandererKillsAPI.get_killmail(killmail_id)
      assert kill["killmail_id"] == killmail_id
    end
  end

  describe "subscribe_to_killmails/3" do
    test "creates subscription and returns subscription ID" do
      subscriber_id = "test_subscriber"
      system_ids = [30_000_142, 30_000_143]
      callback_url = "https://example.com/webhook"

      expected_response = %{
        "subscription_id" => "sub_12345"
      }

      HttpClientMock
      |> expect(:request, fn :post, _url, body, _headers, _opts ->
        decoded_body = Jason.decode!(body)
        assert decoded_body["subscriber_id"] == subscriber_id
        assert decoded_body["system_ids"] == system_ids
        assert decoded_body["callback_url"] == callback_url

        {:ok, %{status_code: 201, body: expected_response}}
      end)

      assert {:ok, "sub_12345"} =
               WandererKillsAPI.subscribe_to_killmails(subscriber_id, system_ids, callback_url)
    end
  end

  describe "bulk_load_system_kills/2" do
    test "successfully loads kills from multiple systems" do
      system_ids = [30_000_142, 30_000_143, 30_000_144]

      # Mock successful responses for chunks
      HttpClientMock
      |> expect(:request, fn :post, _url, _body, _headers, _opts ->
        response = %{
          "systems" => %{
            "30000142" => [%{"killmail_id" => 1}, %{"killmail_id" => 2}],
            "30000143" => [%{"killmail_id" => 3}]
          }
        }

        {:ok, %{status_code: 200, body: response}}
      end)

      assert {:ok, %{loaded: loaded, errors: errors}} =
               WandererKillsAPI.bulk_load_system_kills(system_ids, 24)

      assert loaded == 3
      assert errors == []
    end

    test "handles partial failures in bulk load" do
      system_ids = [30_000_142, 30_000_143]

      # First call succeeds, second fails
      HttpClientMock
      |> expect(:request, fn :post, _url, _body, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:ok, %{loaded: 0, errors: errors}} =
               WandererKillsAPI.bulk_load_system_kills(system_ids, 24)

      assert length(errors) == 1
    end
  end

  describe "health_check/0" do
    test "returns health status when API is up" do
      expected_response = %{
        "status" => "healthy",
        "version" => "1.0.0"
      }

      HttpClientMock
      |> expect(:request, fn :get, url, nil, _headers, _opts ->
        assert url =~ "/api/health"
        {:ok, %{status_code: 200, body: expected_response}}
      end)

      assert {:ok, response} = WandererKillsAPI.health_check()
      assert response["status"] == "healthy"
    end

    test "returns error when API is down" do
      HttpClientMock
      |> expect(:request, fn :get, _url, nil, _headers, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} = WandererKillsAPI.health_check()
    end
  end

  describe "transform_kill/1" do
    test "ensures consistent killmail structure" do
      raw_kill = %{
        "killmail_id" => 12_345,
        "victim" => %{
          "character_id" => 95_123_456
        },
        "attackers" => [
          %{"character_id" => 95_654_321}
        ]
      }

      HttpClientMock
      |> expect(:request, fn :get, _url, nil, _headers, _opts ->
        {:ok, %{status_code: 200, body: raw_kill}}
      end)

      assert {:ok, kill} = WandererKillsAPI.get_killmail(12_345)

      # Check victim normalization
      assert kill["victim"]["character_name"] == nil
      assert kill["victim"]["corporation_name"] == nil
      assert kill["victim"]["alliance_name"] == nil
      assert kill["victim"]["ship_name"] == nil

      # Check attacker normalization
      [attacker | _] = kill["attackers"]
      assert Map.has_key?(attacker, "character_name")
      assert Map.has_key?(attacker, "corporation_name")
      assert Map.has_key?(attacker, "alliance_name")
      assert Map.has_key?(attacker, "ship_name")
    end
  end
end
