defmodule WandererNotifier.CorpTools.ChartTypes do
  @moduledoc """
  Defines all available chart types as constants.

  This module provides a centralized list of chart types available in the application,
  ensuring consistency in references throughout the codebase.

  ## Example

  ```elixir
  alias WandererNotifier.CorpTools.ChartTypes

  def generate_damage_chart(data) do
    ChartService.generate_chart(ChartTypes.damage_final_blows(), data)
  end
  ```
  """

  # Player Performance Charts
  @doc "Damage done and final blows chart"
  def damage_final_blows, do: "damage_final_blows"

  @doc "Character performance chart (kills, solo kills, points)"
  def character_performance, do: "character_performance"

  @doc "Combined losses chart (ship losses and pod losses)"
  def combined_losses, do: "combined_losses"

  # Ship Analysis Charts
  @doc "Our corporation's ships used chart"
  def our_ships_used, do: "our_ships_used"

  @doc "Kills by ship type chart"
  def kills_by_ship_type, do: "kills_by_ship_type"

  @doc "Top ships killed chart"
  def top_ships_killed, do: "top_ships_killed"

  # Temporal Activity Charts
  @doc "Kill activity over time chart"
  def kill_activity_over_time, do: "kill_activity_over_time"

  @doc "Kills heatmap chart (by time of day)"
  def kills_heatmap, do: "kills_heatmap"

  @doc "Fleet size and value killed over time chart"
  def fleet_size_and_value, do: "fleet_size_and_value"

  # Misc. Analysis Charts
  @doc "Kill to loss ratio and efficiency chart"
  def ratio_and_efficiency, do: "ratio_and_efficiency"

  @doc "Victims by corporation chart"
  def victims_by_corporation, do: "victims_by_corporation"

  @doc "Returns all available chart types"
  def all do
    [
      damage_final_blows(),
      character_performance(),
      combined_losses(),
      our_ships_used(),
      kills_by_ship_type(),
      top_ships_killed(),
      kill_activity_over_time(),
      kills_heatmap(),
      fleet_size_and_value(),
      ratio_and_efficiency(),
      victims_by_corporation()
    ]
  end

  @doc """
  Validates if a given string is a recognized chart type.

  ## Parameters

  - type: The chart type string to validate

  ## Returns

  - `true` if it's a valid chart type
  - `false` otherwise
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(type) when is_binary(type) do
    type in all()
  end

  def valid?(_), do: false

  @doc """
  Gets the display name for a chart type.

  ## Parameters

  - type: The chart type string

  ## Returns

  - The display name string or the original if not found
  """
  @spec display_name(String.t()) :: String.t()
  def display_name(type) when is_binary(type) do
    case type do
      "damage_final_blows" -> "Damage and Final Blows"
      "character_performance" -> "Character Performance"
      "combined_losses" -> "Combined Losses"
      "our_ships_used" -> "Our Ships Used"
      "kills_by_ship_type" -> "Kills by Ship Type"
      "top_ships_killed" -> "Top Ships Killed"
      "kill_activity_over_time" -> "Kill Activity Over Time"
      "kills_heatmap" -> "Kills Heatmap"
      "fleet_size_and_value" -> "Fleet Size and Value Killed"
      "ratio_and_efficiency" -> "Kill/Loss Ratio and Efficiency"
      "victims_by_corporation" -> "Victims by Corporation"
      _ -> type
    end
  end
end
