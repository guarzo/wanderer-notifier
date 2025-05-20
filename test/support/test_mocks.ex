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
    # System and Character tracking
    MockSystem
    |> stub(:is_tracked?, fn _id -> true end)

    MockCharacter
    |> stub(:is_tracked?, fn _id -> true end)

    # Deduplication
    MockDeduplication
    |> stub(:check, fn _type, _id -> {:ok, :new} end)

    # Config
    MockConfig
    |> stub(:get_config, fn ->
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
    end)
    |> stub(:notifications_enabled?, fn -> true end)
    |> stub(:kill_notifications_enabled?, fn -> true end)
    |> stub(:system_notifications_enabled?, fn -> true end)
    |> stub(:character_notifications_enabled?, fn -> true end)
    |> stub(:get_notification_setting, fn _, _ -> true end)

    # ESI Service
    WandererNotifier.ESI.ServiceMock
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
    |> stub(:get_character_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Character", "corporation_id" => 300, "alliance_id" => 400}}
    end)
    |> stub(:get_corporation_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)
    |> stub(:get_alliance_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "TEST"}}
    end)
    |> stub(:get_system, fn _id, _opts ->
      {:ok, %{"name" => "Test System", "system_id" => 30_000_142}}
    end)
    |> stub(:get_system_info, fn _id, _opts ->
      {:ok, %{"name" => "Test System", "system_id" => 30_000_142}}
    end)
    |> stub(:get_type_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)
    |> stub(:get_system_kills, fn _id, _limit, _opts ->
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
    end)
    |> stub(:get_character, fn _id, _opts ->
      {:ok, %{"name" => "Test Character", "corporation_id" => 300, "alliance_id" => 400}}
    end)
    |> stub(:get_type, fn _id, _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)
    |> stub(:get_ship_type_name, fn _id, _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)
  end
end
