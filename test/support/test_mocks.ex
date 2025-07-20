defmodule WandererNotifier.TestMocks do
  @moduledoc """
  This module defines the mocks used in tests.
  """

  import Mox

  # Define mocks
  defmock(MockSystem, for: WandererNotifier.Map.TrackingBehaviour)
  defmock(MockCharacter, for: WandererNotifier.Map.TrackingBehaviour)

  defmock(MockDeduplication,
    for: WandererNotifier.Domains.Notifications.Deduplication.DeduplicationBehaviour
  )

  defmock(MockConfig, for: WandererNotifier.Shared.Config.ConfigBehaviour)

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
    |> stub(:is_tracked?, fn _id -> {:ok, true} end)

    MockCharacter
    |> stub(:is_tracked?, fn _id -> {:ok, true} end)
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
    |> stub(:config_module, fn -> MockConfig end)
    |> stub(:deduplication_module, fn -> MockDeduplication end)
    |> stub(:system_track_module, fn -> MockSystem end)
    |> stub(:character_track_module, fn -> MockCharacter end)
    |> stub(:notification_determiner_module, fn -> WandererNotifier.Domains.Notifications.Determiner.Kill end)
    |> stub(:killmail_enrichment_module, fn -> WandererNotifier.Domains.Killmail.Enrichment end)
    |> stub(:killmail_notification_module, fn -> WandererNotifier.Domains.Notifications.KillmailNotification end)
  end

  defp setup_esi_mocks do
    # Use the existing ServiceMock from test/support/mocks/esi_service_mock.ex
    # No need to set up stubs since the mock already has full implementations
    WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
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
end
