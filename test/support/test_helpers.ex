defmodule WandererNotifier.Test.Support.TestHelpers do
  @moduledoc """
  Common test utilities and helpers for WandererNotifier tests.

  Provides standardized:
  - Mock setup and configuration
  - Test data fixtures
  - Common assertion helpers
  - Database and cache cleanup
  """

  import Mox
  import ExUnit.Assertions

  @doc """
  Sets up common Mox mocks with default behaviors.

  Call this in your test setup to get consistent mock behavior:

      setup do
        TestHelpers.setup_mox_defaults()
        :ok
      end
  """
  def setup_mox_defaults do
    # Note: Tests should call set_mox_from_context() and verify_on_exit!() in their setup
    # This function just sets up the default mock behaviors

    # Set up default cache mock behaviors
    setup_cache_mocks()

    # Set up default service mock behaviors
    setup_service_mocks()

    # Set up default client mock behaviors
    setup_client_mocks()

    :ok
  end

  @doc """
  Sets up cache mock with common default behaviors.
  """
  def setup_cache_mocks do
    stub(WandererNotifier.MockCache, :get, fn _key -> {:ok, nil} end)
    stub(WandererNotifier.MockCache, :get, fn _key, _opts -> {:ok, nil} end)
    stub(WandererNotifier.MockCache, :mget, fn _keys -> {:ok, %{}} end)
    stub(WandererNotifier.MockCache, :set, fn _key, value, _ttl -> {:ok, value} end)
    stub(WandererNotifier.MockCache, :put, fn _key, value -> {:ok, value} end)
    stub(WandererNotifier.MockCache, :delete, fn _key -> :ok end)
    stub(WandererNotifier.MockCache, :clear, fn -> :ok end)
    stub(WandererNotifier.MockCache, :get_recent_kills, fn -> [] end)
  end

  @doc """
  Sets up service mocks with common default behaviors.
  """
  def setup_service_mocks do
    setup_esi_service_mocks()
    setup_config_service_mocks()
    setup_deduplication_mocks()
    setup_dispatcher_mocks()
  end

  defp setup_esi_service_mocks do
    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_killmail, fn _id, _hash ->
      {:ok, sample_killmail_data()}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_character, fn _id ->
      {:ok, sample_character_data()}
    end)

    stub(
      WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock,
      :get_corporation_info,
      fn _id ->
        {:ok, sample_corporation_data()}
      end
    )

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_alliance_info, fn _id ->
      {:ok, sample_alliance_data()}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system, fn id, _opts ->
      {:ok, Map.put(sample_system_data(), "name", "System-#{id}")}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_type_info, fn _id ->
      {:ok, sample_type_data()}
    end)
  end

  defp setup_config_service_mocks do
    stub(WandererNotifier.MockConfig, :notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :kill_notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :system_notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :character_notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :get_config, fn -> sample_config_data() end)
  end

  defp setup_deduplication_mocks do
    stub(WandererNotifier.MockDeduplication, :check, fn _type, _id -> {:ok, :new} end)
    stub(WandererNotifier.MockDeduplication, :clear_key, fn _type, _id -> :ok end)
  end

  defp setup_dispatcher_mocks do
    stub(WandererNotifier.MockDispatcher, :send_message, fn _message -> {:ok, :sent} end)
  end

  @doc """
  Sets up client mocks with common default behaviors.
  """
  def setup_client_mocks do
    # HTTP Client defaults
    stub(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
      {:ok, %{status_code: 200, body: "{}"}}
    end)

    stub(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
      {:ok, %{status_code: 200, body: "{}"}}
    end)

    # Use centralized tracking defaults
    setup_tracking_defaults()
  end

  @doc """
  Creates sample killmail data for testing.
  """
  def sample_killmail_data do
    %{
      "killmail_id" => 123_456,
      "killmail_time" => "2024-01-01T12:00:00Z",
      "solar_system_id" => 30_000_142,
      "victim" => %{
        "character_id" => 1001,
        "corporation_id" => 2001,
        "alliance_id" => 3001,
        "ship_type_id" => 587,
        "damage_taken" => 5000
      },
      "attackers" => [
        %{
          "character_id" => 1002,
          "corporation_id" => 2002,
          "ship_type_id" => 588,
          "final_blow" => true,
          "damage_done" => 5000
        }
      ]
    }
  end

  @doc """
  Creates sample character data for testing.
  """
  def sample_character_data do
    %{
      "name" => "Test Character",
      "corporation_id" => 2001,
      "alliance_id" => 3001,
      "security_status" => -1.5
    }
  end

  @doc """
  Creates sample corporation data for testing.
  """
  def sample_corporation_data do
    %{
      "name" => "Test Corporation",
      "ticker" => "TEST",
      "alliance_id" => 3001,
      "member_count" => 100
    }
  end

  @doc """
  Creates sample alliance data for testing.
  """
  def sample_alliance_data do
    %{
      "name" => "Test Alliance",
      "ticker" => "TESTA",
      "corporations_count" => 5
    }
  end

  @doc """
  Creates sample system data for testing.
  """
  def sample_system_data do
    %{
      "name" => "Jita",
      "security_status" => 0.946,
      "constellation_id" => 20_000_020,
      "region_id" => 10_000_002
    }
  end

  @doc """
  Creates sample type data for testing.
  """
  def sample_type_data do
    %{
      "name" => "Rifter",
      "group_id" => 25,
      "category_id" => 6,
      "volume" => 27_289.5
    }
  end

  @doc """
  Creates sample config data for testing.
  """
  def sample_config_data do
    %{
      notifications_enabled: true,
      kill_notifications_enabled: true,
      system_notifications_enabled: true,
      character_notifications_enabled: true
    }
  end

  @doc """
  Creates a test killmail struct with reasonable defaults.

  Options:
  - killmail_id: integer (default: 123456)
  - victim_id: integer (default: 1001)
  - attacker_id: integer (default: 1002)
  - system_id: integer (default: 30000142)
  - ship_type_id: integer (default: 587)
  """
  def create_test_killmail(opts \\ []) do
    killmail_id = Keyword.get(opts, :killmail_id, 123_456)
    victim_id = Keyword.get(opts, :victim_id, 1001)
    attacker_id = Keyword.get(opts, :attacker_id, 1002)
    system_id = Keyword.get(opts, :system_id, 30_000_142)
    ship_type_id = Keyword.get(opts, :ship_type_id, 587)

    %WandererNotifier.Domains.Killmail.Killmail{
      killmail_id: killmail_id,
      zkb: %{
        "locationID" => system_id,
        "hash" => "test_hash_#{killmail_id}",
        "fittedValue" => 100_000_000,
        "totalValue" => 150_000_000,
        "points" => 1,
        "npc" => false,
        "solo" => false,
        "awox" => false
      },
      esi_data: %{
        "killmail_id" => killmail_id,
        "killmail_time" => "2024-01-01T12:00:00Z",
        "solar_system_id" => system_id,
        "victim" => %{
          "character_id" => victim_id,
          "corporation_id" => 2001,
          "ship_type_id" => ship_type_id,
          "damage_taken" => 5000
        },
        "attackers" => [
          %{
            "character_id" => attacker_id,
            "corporation_id" => 2002,
            "ship_type_id" => ship_type_id + 1,
            "final_blow" => true,
            "damage_done" => 5000
          }
        ]
      },
      victim_name: "Test Victim",
      victim_corporation: "Test Corp",
      victim_corp_ticker: "TEST",
      victim_alliance: "Test Alliance",
      ship_name: "Rifter",
      system_name: "Jita",
      system_id: system_id,
      attackers: ["Test Attacker"],
      value: 150_000_000
    }
  end

  @doc """
  Sets up tracking mocks to return specific tracking states.

  Options:
  - tracked_systems: list of system IDs that should return true
  - tracked_characters: list of character IDs that should return true
  """
  def setup_tracking_mocks(opts \\ []) do
    tracked_systems = Keyword.get(opts, :tracked_systems, [])
    tracked_characters = Keyword.get(opts, :tracked_characters, [])

    stub(WandererNotifier.MockSystem, :is_tracked?, fn id ->
      {:ok, id in tracked_systems}
    end)

    stub(WandererNotifier.MockCharacter, :is_tracked?, fn id ->
      {:ok, id in tracked_characters}
    end)
  end

  @doc """
  Sets up HTTP mock to return specific responses for URLs.

  Example:
      setup_http_mocks(%{
        "https://api.example.com/test" => {:ok, %{status_code: 200, body: "success"}},
        "https://api.example.com/error" => {:error, :timeout}
      })
  """
  def setup_http_mocks(url_responses) when is_map(url_responses) do
    stub(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
      Map.get(url_responses, url, {:ok, %{status_code: 404, body: "Not Found"}})
    end)

    stub(WandererNotifier.HTTPMock, :post, fn url, _body, _headers, _opts ->
      Map.get(url_responses, url, {:ok, %{status_code: 404, body: "Not Found"}})
    end)
  end

  @doc """
  Sets up cache mock to return specific values for keys.

  Example:
      setup_cache_responses(%{
        "character:1001" => {:ok, %{name: "Test Character"}},
        "system:30000142" => {:ok, %{name: "Jita"}}
      })
  """
  def setup_cache_responses(key_responses) when is_map(key_responses) do
    stub(WandererNotifier.MockCache, :get, fn key ->
      Map.get(key_responses, key, {:ok, nil})
    end)

    stub(WandererNotifier.MockCache, :get, fn key, _opts ->
      Map.get(key_responses, key, {:ok, nil})
    end)
  end

  @doc """
  Cleans up test environment (cache, ETS tables, etc.)
  """
  def cleanup_test_environment do
    # Clear cache if it exists
    if Process.whereis(:wanderer_test_cache) do
      Cachex.clear(:wanderer_test_cache)
    end

    # Clear ETS tables
    clear_ets_table(:cache_table)
    clear_ets_table(:locks_table)
  end

  @doc """
  Asserts that a result is an error tuple with the expected reason.
  """
  def assert_error(result, expected_reason) do
    assert {:error, ^expected_reason} = result
  end

  @doc """
  Asserts that a result is an ok tuple and returns the value.
  """
  def assert_ok(result) do
    assert {:ok, value} = result
    value
  end

  @doc """
  Asserts that a result is an ok tuple with the expected value.
  """
  def assert_ok(result, expected_value) do
    assert {:ok, ^expected_value} = result
  end

  @doc """
  Waits for a mock to be called a specific number of times.
  Useful for async operations.
  """
  def wait_for_mock_calls(mock_module, function, arity, expected_calls, timeout \\ 1000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_calls(mock_module, function, arity, expected_calls, end_time)
  end

  @doc """
  Creates a temporary test environment variable.
  Automatically cleans up after the test.
  """
  def with_env(env_vars, test_fun) when is_map(env_vars) and is_function(test_fun, 0) do
    # Store original values
    original_values =
      Enum.map(env_vars, fn {key, _value} ->
        {key, System.get_env(key)}
      end)
      |> Enum.into(%{})

    # Set test values
    Enum.each(env_vars, fn {key, value} ->
      System.put_env(key, value)
    end)

    try do
      test_fun.()
    after
      # Restore original values
      Enum.each(original_values, fn {key, original_value} ->
        if original_value do
          System.put_env(key, original_value)
        else
          System.delete_env(key)
        end
      end)
    end
  end

  @doc """
  Sets up common tracking-related mocks.
  This centralizes the MockSystem.is_tracked?/1 stub that was duplicated across tests.
  """
  def setup_tracking_defaults do
    stub(WandererNotifier.MockSystem, :is_tracked?, fn _id -> {:ok, false} end)
    stub(WandererNotifier.MockCharacter, :is_tracked?, fn _id -> {:ok, false} end)
  end

  # Private helpers

  defp clear_ets_table(table_name) do
    if :ets.whereis(table_name) != :undefined do
      :ets.delete_all_objects(table_name)
    end
  end

  defp wait_for_calls(_mock_module, _function, _arity, expected_calls, _end_time)
       when expected_calls <= 0 do
    :ok
  end

  defp wait_for_calls(mock_module, function, arity, expected_calls, end_time) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      flunk(
        "Expected #{expected_calls} calls to #{mock_module}.#{function}/#{arity} but timeout reached"
      )
    else
      # Check if we've received enough calls by attempting to verify
      try do
        verify!(mock_module)
        :ok
      rescue
        Mox.VerificationError ->
          Process.sleep(10)
          wait_for_calls(mock_module, function, arity, expected_calls, end_time)
      end
    end
  end
end
