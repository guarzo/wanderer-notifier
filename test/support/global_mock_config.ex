defmodule WandererNotifier.Test.Support.GlobalMockConfig do
  @moduledoc """
  Global mock config that works across processes for async Tasks.
  """

  @behaviour WandererNotifier.Shared.Config.ConfigBehaviour

  def notifications_enabled?, do: true
  def kill_notifications_enabled?, do: true
  def system_notifications_enabled?, do: true
  def character_notifications_enabled?, do: true

  def get_notification_setting(_type, _key), do: {:ok, true}

  def get_config do
    {:ok,
     %{
       notifications: %{
         enabled: true,
         kill: %{
           enabled: true,
           system: %{enabled: true},
           character: %{enabled: true},
           min_value: 100_000_000,
           min_isk_per_character: 50_000_000,
           min_isk_per_corporation: 50_000_000,
           min_isk_per_alliance: 50_000_000,
           min_isk_per_ship: 50_000_000,
           min_isk_per_system: 50_000_000
         }
       }
     }}
  end

  def deduplication_module, do: WandererNotifier.MockDeduplication
  def system_track_module, do: WandererNotifier.MockSystem
  def character_track_module, do: WandererNotifier.MockCharacter
  def notification_determiner_module, do: WandererNotifier.Domains.Notifications.Determiner.Kill
  def killmail_enrichment_module, do: WandererNotifier.Domains.Killmail.Enrichment

  def killmail_notification_module,
    do: WandererNotifier.Domains.Notifications.KillmailNotification

  def config_module, do: WandererNotifier.MockConfig
end
