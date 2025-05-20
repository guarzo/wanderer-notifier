defmodule WandererNotifier.TestMocks do
  @moduledoc """
  This module defines the mocks used in tests.
  """

  import Mox

  # Define mocks
  defmock(MockSystem, for: WandererNotifier.Map.SystemBehaviour)
  defmock(MockCharacter, for: WandererNotifier.Map.CharacterBehaviour)
  defmock(MockDeduplication, for: WandererNotifier.Notifications.Deduplication.Behaviour)
  defmock(MockConfig, for: WandererNotifier.Config.ConfigBehaviour)
  defmock(WandererNotifier.ESI.ServiceMock, for: WandererNotifier.ESI.ServiceBehaviour)

  @doc """
  Sets up default stubs for all mocks.
  """
  def setup_default_stubs do
    setup_tracking_mocks()
    setup_deduplication_mocks()
    setup_config_mocks()
    setup_esi_mocks()
  end

  defp setup_tracking_mocks do
    MockSystem
    |> stub(:is_tracked?, fn _id -> true end)

    MockCharacter
    |> stub(:is_tracked?, fn _id -> true end)
  end

  defp setup_deduplication_mocks do
    MockDeduplication
    |> stub(:check, fn _type, _id -> {:ok, :new} end)
  end

  defp setup_config_mocks do
    MockConfig
    |> stub(:get_config, &get_default_config/0)
    |> stub(:notifications_enabled?, fn -> true end)
    |> stub(:kill_notifications_enabled?, fn -> true end)
    |> stub(:system_notifications_enabled?, fn -> true end)
    |> stub(:character_notifications_enabled?, fn -> true end)
    |> stub(:get_notification_setting, fn _, _ -> true end)
  end

  defp setup_esi_mocks do
    WandererNotifier.ESI.ServiceMock
    |> setup_killmail_mocks()
    |> setup_character_mocks()
    |> setup_corporation_mocks()
    |> setup_alliance_mocks()
    |> setup_system_mocks()
    |> setup_type_mocks()
  end

  defp setup_killmail_mocks(mock) do
    mock
    |> stub(:get_killmail, &get_killmail/3)
    |> stub(:get_system_kills, &get_system_kills/3)
  end

  defp setup_character_mocks(mock) do
    mock
    |> stub(:get_character_info, &get_character_info/2)
    |> stub(:get_character, &get_character_info/2)
  end

  defp setup_corporation_mocks(mock) do
    mock
    |> stub(:get_corporation_info, &get_corporation_info/2)
  end

  defp setup_alliance_mocks(mock) do
    mock
    |> stub(:get_alliance_info, &get_alliance_info/2)
  end

  defp setup_system_mocks(mock) do
    mock
    |> stub(:get_system, &get_system/2)
    |> stub(:get_system_info, &get_system/2)
  end

  defp setup_type_mocks(mock) do
    mock
    |> stub(:get_type_info, &get_type_info/2)
    |> stub(:get_type, &get_type_info/2)
    |> stub(:get_ship_type_name, &get_type_info/2)
  end

  # Mock response functions
  defp get_default_config do
    {:ok,
     %{
       notifications: %{
         enabled: true,
         kill: %{
           enabled: true,
           min_value: 100_000_000,
           min_isk_per_character: 10_000_000,
           min_isk_per_corporation: 50_000_000,
           min_isk_per_alliance: 100_000_000,
           min_isk_per_ship: 50_000_000,
           min_isk_per_system: 50_000_000,
           min_isk_per_region: 50_000_000,
           min_isk_per_constellation: 50_000_000,
           min_isk_per_character_in_corporation: 10_000_000,
           min_isk_per_character_in_alliance: 10_000_000,
           min_isk_per_corporation_in_alliance: 50_000_000,
           min_isk_per_ship_in_corporation: 50_000_000,
           min_isk_per_ship_in_alliance: 50_000_000,
           min_isk_per_ship_in_system: 50_000_000,
           min_isk_per_ship_in_region: 50_000_000,
           min_isk_per_ship_in_constellation: 50_000_000,
           min_isk_per_system_in_region: 50_000_000,
           min_isk_per_system_in_constellation: 50_000_000,
           min_isk_per_region_in_constellation: 50_000_000,
           min_isk_per_constellation_in_region: 50_000_000,
           min_isk_per_character_in_system: 10_000_000,
           min_isk_per_character_in_region: 10_000_000,
           min_isk_per_character_in_constellation: 10_000_000,
           min_isk_per_corporation_in_system: 50_000_000,
           min_isk_per_corporation_in_region: 50_000_000,
           min_isk_per_corporation_in_constellation: 50_000_000,
           min_isk_per_alliance_in_system: 100_000_000,
           min_isk_per_alliance_in_region: 100_000_000,
           min_isk_per_alliance_in_constellation: 100_000_000
         }
       }
     }}
  end

  defp get_killmail(_id, _hash, _opts) do
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
  end

  defp get_character_info(_id, _opts) do
    {:ok, %{"name" => "Test Character", "corporation_id" => 300, "alliance_id" => 400}}
  end

  defp get_corporation_info(_id, _opts) do
    {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
  end

  defp get_alliance_info(_id, _opts) do
    {:ok, %{"name" => "Test Alliance", "ticker" => "TEST"}}
  end

  defp get_system(_id, _opts) do
    {:ok, %{"name" => "Test System", "system_id" => 30_000_142}}
  end

  defp get_type_info(_id, _opts) do
    {:ok, %{"name" => "Test Ship"}}
  end

  defp get_system_kills(_id, _limit, _opts) do
    {:ok,
     [
       %{
         "killmail_id" => 123,
         "killmail_hash" => "abc123",
         "killmail_time" => "2020-01-01T00:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 100,
           "corporation_id" => 300,
           "alliance_id" => 400,
           "ship_type_id" => 200
         }
       }
     ]}
  end
end
