defmodule WandererNotifier.Core.ConfigBehaviour do
  @moduledoc """
  Behaviour definition for configuration management.
  Defines the contract that any implementation must fulfill.
  """

  @doc """
  Gets the Discord channel ID for a specific feature.

  ## Parameters
  - `feature`: The feature to get the channel ID for

  ## Returns
  - `String.t()`: The Discord channel ID for the feature
  """
  @callback discord_channel_id_for(feature :: atom()) :: String.t()

  @doc """
  Checks if kill charts feature is enabled.

  ## Returns
  - `boolean()`: Whether kill charts are enabled
  """
  @callback kill_charts_enabled?() :: boolean()
end
