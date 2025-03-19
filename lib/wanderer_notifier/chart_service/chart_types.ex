defmodule WandererNotifier.ChartService.ChartTypes do
  @moduledoc """
  Constants for chart types used throughout the application.

  This module provides a centralized set of constants for all chart types,
  ensuring consistency across adapters and preventing duplication.
  """

  # Standard chart types
  @doc "Bar chart type"
  def bar, do: "bar"

  @doc "Line chart type"
  def line, do: "line"

  @doc "Horizontal bar chart type"
  def horizontal_bar, do: "horizontalBar"

  @doc "Doughnut chart type"
  def doughnut, do: "doughnut"

  @doc "Pie chart type"
  def pie, do: "pie"

  # Chart feature types (used for identifying specific charts)
  @doc "Damage and final blows chart"
  def damage_final_blows, do: "damage_final_blows"

  @doc "Combined losses chart"
  def combined_losses, do: "combined_losses"

  @doc "Kill activity chart"
  def kill_activity, do: "kill_activity"

  @doc "Activity summary chart"
  def activity_summary, do: "activity_summary"

  @doc "Activity timeline chart"
  def activity_timeline, do: "activity_timeline"

  @doc "Activity distribution chart"
  def activity_distribution, do: "activity_distribution"

  @doc "Kills by ship type chart"
  def kills_by_ship_type, do: "kills_by_ship_type"

  @doc "Kills by month chart"
  def kills_by_month, do: "kills_by_month"

  @doc "Total kills value chart"
  def total_kills_value, do: "total_kills_value"

  @doc "Character performance chart"
  def character_performance, do: "character_performance"
end
