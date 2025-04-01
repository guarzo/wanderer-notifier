defmodule WandererNotifier.Notifiers.Discord.ComponentBuilder do
  @moduledoc """
  Utility module for building Discord UI components.
  Provides functions to create buttons, select menus, and action rows.
  """

  alias WandererNotifier.Notifiers.Discord.Constants

  @doc """
  Creates an action row component.
  Action rows are containers for other components.

  ## Parameters
    - components: List of components to include in the row

  ## Returns
    - A map representing an action row
  """
  def action_row(components) do
    %{
      # Action Row
      "type" => 1,
      "components" => components
    }
  end

  @doc """
  Creates a button component.

  ## Parameters
    - label: The button label text
    - custom_id: Identifier for the button (required for non-link buttons)
    - style: Button style (:primary, :secondary, :success, :danger, :link)
    - options: Additional options (emoji, url for link buttons, disabled flag)

  ## Returns
    - A map representing a button component
  """
  def button(label, custom_id, style \\ :primary, options \\ %{}) do
    # Validate style and custom_id/url requirements
    style_value = Constants.button_style(style)

    # Handle link style special case (requires URL instead of custom_id)
    {id_field, id_value} =
      if style == :link do
        {"url", Map.get(options, :url, "https://example.com")}
      else
        {"custom_id", custom_id}
      end

    # Build button with required fields
    %{
      "type" => Constants.component_type(:button),
      "style" => style_value,
      "label" => label,
      id_field => id_value
    }
    |> add_button_options(options)
  end

  @doc """
  Creates a select menu component.

  ## Parameters
    - custom_id: Identifier for the select menu
    - options: List of options for the select menu
    - placeholder: Placeholder text
    - additional_options: Additional select menu options

  ## Returns
    - A map representing a select menu component
  """
  def select_menu(custom_id, options, placeholder \\ nil, additional_options \\ %{}) do
    menu = %{
      "type" => Constants.component_type(:select_menu),
      "custom_id" => custom_id,
      "options" => options
    }

    menu = if placeholder, do: Map.put(menu, "placeholder", placeholder), else: menu

    # Add additional options like min/max values, disabled flag
    Enum.reduce(additional_options, menu, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  @doc """
  Creates a select menu option.

  ## Parameters
    - label: Display text for the option
    - value: Value submitted when this option is selected
    - description: Optional description text
    - default: Whether this option is selected by default
    - emoji: Optional emoji to display

  ## Returns
    - A map representing a select menu option
  """
  def select_option(label, value, description \\ nil, default \\ false, emoji \\ nil) do
    option = %{
      "label" => label,
      "value" => value,
      "default" => default
    }

    option = if description, do: Map.put(option, "description", description), else: option
    option = if emoji, do: Map.put(option, "emoji", emoji), else: option

    option
  end

  @doc """
  Creates a kill notification action row with zKillboard link button.

  ## Parameters
    - kill_id: The ID of the kill for the zKillboard link

  ## Returns
    - A map representing an action row with a zKillboard button
  """
  def kill_action_row(kill_id) do
    zkill_url = "https://zkillboard.com/kill/#{kill_id}/"

    action_row([
      button("View on zKillboard", "zkill_#{kill_id}", :link, %{url: zkill_url})
    ])
  end

  # Private helper to add optional button properties
  defp add_button_options(button, options) do
    button
    |> maybe_add_option(options, :disabled)
    |> maybe_add_option(options, :emoji)
  end

  # Helper to conditionally add an option if present in the options map
  defp maybe_add_option(component, options, option_key) do
    case Map.get(options, option_key) do
      nil -> component
      value -> Map.put(component, to_string(option_key), value)
    end
  end
end
