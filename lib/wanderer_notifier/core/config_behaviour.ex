defmodule WandererNotifier.Core.ConfigBehaviour do
  @moduledoc """
  Behaviour module for configuration functionality.
  Defines the contract for configuration-related operations.
  """

  @callback get_config(atom(), any()) :: any()
  @callback get_env() :: atom()
  @callback map_charts_enabled?() :: boolean()
  @callback kill_charts_enabled?() :: boolean()
  @callback discord_channel_id_for_activity_charts() :: String.t() | nil
  @callback discord_channel_id_for(atom()) :: String.t() | nil
end
