defmodule WandererNotifier.Domains.Notifications.Determiner.KillBehaviour do
  @moduledoc """
  Behaviour definition for Kill notification determiner
  """

  @type kill_data :: map() | WandererNotifier.Domains.Killmail.Killmail.t()

  @callback should_notify?(kill_data) ::
              {:ok, %{should_notify: boolean(), reason: String.t() | nil}}
  @callback get_kill_system_id(kill_data) :: String.t() | nil
  @callback tracked_system?(system_id :: String.t() | integer() | nil) :: boolean()
  @callback has_tracked_character?(data :: map()) :: boolean()
  @callback tracked_character?(character_id :: String.t() | integer()) :: boolean()
  @callback get_tracked_characters(kill_data) :: [String.t()]
  @callback are_tracked_characters_victims?(kill_data, tracked_chars :: [String.t()]) :: boolean()
end
