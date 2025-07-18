defmodule WandererNotifier.Killmail.FallbackHandlerTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.FallbackHandler
  alias WandererNotifier.HTTPMock, as: HttpClientMock
  alias WandererNotifier.ExternalAdaptersMock

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # Set up mocks
    Application.put_env(:wanderer_notifier, :http_client, HttpClientMock)
    Application.put_env(:wanderer_notifier, :external_adapters_impl, ExternalAdaptersMock)

    # Start the FallbackHandler
    {:ok, pid} = FallbackHandler.start_link([])

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, handler_pid: pid}
  end

  describe "websocket_down/0" do
    test "activates fallback mode and fetches recent data" do
      # Mock tracked systems
      ExternalAdaptersMock
      |> expect(:get_tracked_systems, fn ->
        {:ok,
         [
           %{solar_system_id: 30_000_142},
           %{solar_system_id: 30_000_143}
         ]}
      end)
      |> expect(:get_tracked_characters, fn ->
        {:ok, []}
      end)

      # Mock HTTP response for systems
      HttpClientMock
      |> expect(:get, fn url, _headers, _opts ->
        if url =~ "30000142%2C30000143" do
          response = %{
            "systems" => %{
              "30000142" => [
                %{
                  "killmail_id" => 12_345,
                  "system_id" => 30_000_142,
                  "victim" => %{},
                  "attackers" => []
                }
              ],
              "30000143" => []
            }
          }

          {:ok, %{status_code: 200, body: Jason.encode!(response)}}
        else
          {:ok, %{status_code: 200, body: Jason.encode!(%{})}}
        end
      end)

      # Notify WebSocket is down
      FallbackHandler.websocket_down()

      # Give it time to process
      Process.sleep(100)

      # Verify fallback is active
      state = :sys.get_state(FallbackHandler)
      assert state.fallback_active == true
    end
  end

  describe "websocket_connected/0" do
    test "deactivates fallback mode" do
      # First activate fallback
      FallbackHandler.websocket_down()
      Process.sleep(50)

      # Then notify connection restored
      FallbackHandler.websocket_connected()
      Process.sleep(50)

      # Verify fallback is inactive
      state = :sys.get_state(FallbackHandler)
      assert state.fallback_active == false
    end
  end

  describe "fetch_recent_data/0" do
    test "fetches data for all tracked systems" do
      # Mock tracked systems
      ExternalAdaptersMock
      |> expect(:get_tracked_systems, fn ->
        {:ok,
         [
           %{solar_system_id: 30_000_142},
           %{solar_system_id: 30_000_143}
         ]}
      end)
      |> expect(:get_tracked_characters, fn ->
        {:ok,
         [
           %{"eve_id" => 95_123_456}
         ]}
      end)

      # Mock HTTP response
      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        response = %{
          "systems" => %{
            "30000142" => [%{"killmail_id" => 1}],
            "30000143" => [%{"killmail_id" => 2}]
          }
        }

        {:ok, %{status_code: 200, body: Jason.encode!(response)}}
      end)

      assert {:ok, result} = FallbackHandler.fetch_recent_data()
      assert result.systems_checked == 2
      assert result.killmails_processed == 2
    end
  end

  describe "bulk_load/1" do
    test "performs bulk loading of historical data" do
      # Mock tracked systems
      ExternalAdaptersMock
      |> expect(:get_tracked_systems, fn ->
        {:ok,
         [
           %{solar_system_id: 30_000_142}
         ]}
      end)
      |> expect(:get_tracked_characters, fn ->
        {:ok, []}
      end)

      # Mock bulk load response
      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        response = %{
          "systems" => %{
            "30000142" => [
              %{"killmail_id" => 1},
              %{"killmail_id" => 2},
              %{"killmail_id" => 3}
            ]
          }
        }

        {:ok, %{status_code: 200, body: Jason.encode!(response)}}
      end)

      assert {:ok, %{loaded: 3, errors: []}} = FallbackHandler.bulk_load(12)
    end
  end

  describe "system_id extraction" do
    test "handles various system data formats" do
      ExternalAdaptersMock
      |> expect(:get_tracked_systems, fn ->
        {:ok,
         [
           %{solar_system_id: 30_000_142},
           %{system_id: 30_000_143},
           %{id: 30_000_144},
           %{"solar_system_id" => 30_000_145},
           %{"system_id" => "30000146"}
         ]}
      end)
      |> expect(:get_tracked_characters, fn ->
        {:ok, []}
      end)

      # Trigger an update
      FallbackHandler.websocket_down()
      Process.sleep(50)

      state = :sys.get_state(FallbackHandler)
      system_ids = MapSet.to_list(state.tracked_systems)

      # Should extract all valid system IDs
      assert 30_000_142 in system_ids
      assert 30_000_143 in system_ids
      assert 30_000_144 in system_ids
      assert 30_000_145 in system_ids
      # String "30000146" should not be included as extract_system_id doesn't handle strings
    end
  end

  describe "character_id extraction" do
    test "handles various character data formats" do
      ExternalAdaptersMock
      |> expect(:get_tracked_systems, fn ->
        {:ok, []}
      end)
      |> expect(:get_tracked_characters, fn ->
        {:ok,
         [
           %{"eve_id" => 95_123_456},
           %{eve_id: 95_123_457},
           %{"eve_id" => "95123458"},
           %{"eve_id" => "invalid"},
           %{"wrong_field" => 95_123_459}
         ]}
      end)

      # Trigger an update
      FallbackHandler.websocket_down()
      Process.sleep(50)

      state = :sys.get_state(FallbackHandler)
      character_ids = MapSet.to_list(state.tracked_characters)

      # Should extract valid character IDs
      assert 95_123_456 in character_ids
      assert 95_123_457 in character_ids
      assert 95_123_458 in character_ids
      # Invalid and wrong_field should be filtered out
      assert length(character_ids) == 3
    end
  end
end
