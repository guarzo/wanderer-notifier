defmodule WandererNotifier.Infrastructure.Adapters.ESI.ServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Infrastructure.Adapters.ESI.Service
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock

  # Test data
  @character_data %{
    "character_id" => 123_456,
    "name" => "Test Character",
    "corporation_id" => 789_012,
    "alliance_id" => 345_678,
    "security_status" => 0.5,
    "birthday" => "2020-01-01T00:00:00Z"
  }

  @corporation_data %{
    "corporation_id" => 789_012,
    "name" => "Test Corporation",
    "ticker" => "TSTC",
    "member_count" => 100,
    "alliance_id" => 345_678,
    "description" => "A test corporation",
    "date_founded" => "2020-01-01T00:00:00Z"
  }

  @alliance_data %{
    "alliance_id" => 345_678,
    "name" => "Test Alliance",
    "ticker" => "TSTA",
    "executor_corporation_id" => 789_012,
    "creator_id" => 123_456,
    "date_founded" => "2020-01-01T00:00:00Z",
    "faction_id" => 555_555
  }

  @system_data %{
    "system_id" => 30_000_142,
    "name" => "Test System",
    "constellation_id" => 20_000_020,
    "security_status" => 0.9,
    "security_class" => "B",
    "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
    "star_id" => 40_000_001,
    "planets" => [%{"planet_id" => 50_000_001}],
    "region_id" => 10_000_002
  }

  # Make sure mocks are verified after each test
  setup :set_mox_from_context
  setup :verify_on_exit!

  # Stub the Client module
  setup do
    # Make sure the required registries are started
    started_registry? =
      case Process.whereis(WandererNotifier.Cache.Registry) do
        nil ->
          {:ok, _} = Registry.start_link(keys: :unique, name: WandererNotifier.Cache.Registry)
          true

        _ ->
          false
      end

    # Make sure Cachex is started for testing
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)

    # Start Cachex if it's not already running
    _cache_started? =
      case Process.whereis(cache_name) do
        nil ->
          # Ensure Cachex application is started
          Application.ensure_all_started(:cachex)
          {:ok, _pid} = Cachex.start_link(name: cache_name, stats: true)
          true

        _pid ->
          false
      end

    # Capture and set the ESI client mock as the implementation
    prev_client = Application.get_env(:wanderer_notifier, :esi_client)
    Application.put_env(:wanderer_notifier, :esi_client, ServiceMock)

    on_exit(fn ->
      # Restore original ESI client
      if prev_client do
        Application.put_env(:wanderer_notifier, :esi_client, prev_client)
      else
        Application.delete_env(:wanderer_notifier, :esi_client)
      end

      # Clean up started processes
      # Note: Cachex doesn't provide a stop/1 function, let supervisor handle cleanup
      if started_registry? do
        case Process.whereis(WandererNotifier.Cache.Registry) do
          nil -> :ok
          pid -> Process.exit(pid, :normal)
        end
      end
    end)

    # Define mocks for ESI client calls
    ServiceMock
    |> stub(:get_character_info, &get_character_info/2)
    |> stub(:get_corporation_info, &get_corporation_info/2)
    |> stub(:get_alliance_info, &get_alliance_info/2)
    |> stub(:get_system, &get_system_info/1)
    |> stub(:get_system, &get_system_info/2)
    |> stub(:get_system_info, &get_system_info/2)
    |> stub(:get_type_info, fn _id, _opts -> {:ok, %{"name" => "Test Ship"}} end)
    |> stub(:get_system_kills, fn _id, _limit, _opts -> {:ok, []} end)
    |> stub(:get_character, &get_character_info/2)
    |> stub(:get_type, fn _id, _opts -> {:ok, %{"name" => "Test Ship"}} end)
    |> stub(:get_ship_type_name, fn _id, _opts -> {:ok, %{"name" => "Test Ship"}} end)
    |> stub(:get_killmail, fn _id, _hash ->
      {:ok,
       %{
         "killmail_id" => 123,
         "killmail_time" => "2020-01-01T00:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 100,
           "corporation_id" => 300,
           "alliance_id" => 400,
           "ship_type_id" => 200
         }
       }}
    end)
    |> stub(:get_killmail, fn _id, _hash, _opts ->
      {:ok,
       %{
         "killmail_id" => 123,
         "killmail_time" => "2020-01-01T00:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 100,
           "corporation_id" => 300,
           "alliance_id" => 400,
           "ship_type_id" => 200
         }
       }}
    end)

    # Return test data for use in tests
    %{
      character_data: @character_data,
      corporation_data: @corporation_data,
      alliance_data: @alliance_data,
      system_data: @system_data
    }
  end

  defp get_character_info(id, _opts) do
    case id do
      123_456 -> {:ok, @character_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_corporation_info(id, _opts) do
    case id do
      789_012 -> {:ok, @corporation_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_alliance_info(id, _opts) do
    case id do
      345_678 -> {:ok, @alliance_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_system_info(id) do
    get_system_info(id, [])
  end

  defp get_system_info(id, _opts) do
    case id do
      30_000_142 -> {:ok, @system_data}
      _ -> {:error, :not_found}
    end
  end

  describe "get_killmail/2" do
    test "returns killmail data" do
      assert {:ok, killmail} = Service.get_killmail(123, "hash")

      assert killmail == %{
               "killmail_id" => 123,
               "killmail_time" => "2020-01-01T00:00:00Z",
               "solar_system_id" => 30_000_142,
               "victim" => %{
                 "character_id" => 100,
                 "corporation_id" => 300,
                 "alliance_id" => 400,
                 "ship_type_id" => 200
               }
             }
    end
  end

  describe "get_killmail/3" do
    test "returns killmail data with opts" do
      assert {:ok, killmail} = Service.get_killmail(123, "hash", [])

      assert killmail == %{
               "killmail_id" => 123,
               "killmail_time" => "2020-01-01T00:00:00Z",
               "solar_system_id" => 30_000_142,
               "victim" => %{
                 "character_id" => 100,
                 "corporation_id" => 300,
                 "alliance_id" => 400,
                 "ship_type_id" => 200
               }
             }
    end
  end
end
