defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.ComponentBuilder do
  @moduledoc """
  Builds Discord message components like buttons and action rows.
  """

  @doc """
  Creates an action row for kill-related actions.
  """
  def kill_action_row(kill_id) do
    %{
      # Action Row
      type: 1,
      components: [
        build_zkill_button(kill_id),
        build_info_button(kill_id)
      ]
    }
  end

  @doc """
  Creates a button that links to zKillboard.
  """
  def build_zkill_button(kill_id) do
    %{
      # Button
      type: 2,
      # Link style
      style: 5,
      label: "View on zKillboard",
      url: "https://zkillboard.com/kill/#{kill_id}/"
    }
  end

  @doc """
  Creates an info button for additional kill details.
  """
  def build_info_button(kill_id) do
    %{
      # Button
      type: 2,
      # Primary style
      style: 1,
      label: "More Info",
      custom_id: "kill_info_#{kill_id}"
    }
  end

  @doc """
  Creates an action row for system-related actions.
  """
  def system_action_row(system_id) do
    %{
      # Action Row
      type: 1,
      components: [
        build_dotlan_button(system_id),
        build_system_info_button(system_id)
      ]
    }
  end

  @doc """
  Creates a button that links to DOTLAN.
  """
  def build_dotlan_button(system_id) do
    %{
      # Button
      type: 2,
      # Link style
      style: 5,
      label: "View on DOTLAN",
      url: "https://evemaps.dotlan.net/system/#{system_id}"
    }
  end

  @doc """
  Creates an info button for additional system details.
  """
  def build_system_info_button(system_id) do
    %{
      # Button
      type: 2,
      # Primary style
      style: 1,
      label: "System Info",
      custom_id: "system_info_#{system_id}"
    }
  end

  @doc """
  Creates an action row for character-related actions.
  """
  def character_action_row(character_id) do
    %{
      # Action Row
      type: 1,
      components: [
        build_zkill_character_button(character_id),
        build_character_info_button(character_id)
      ]
    }
  end

  @doc """
  Creates a button that links to a character's zKillboard page.
  """
  def build_zkill_character_button(character_id) do
    %{
      # Button
      type: 2,
      # Link style
      style: 5,
      label: "View on zKillboard",
      url: "https://zkillboard.com/character/#{character_id}/"
    }
  end

  @doc """
  Creates an info button for additional character details.
  """
  def build_character_info_button(character_id) do
    %{
      # Button
      type: 2,
      # Primary style
      style: 1,
      label: "Character Info",
      custom_id: "character_info_#{character_id}"
    }
  end
end
