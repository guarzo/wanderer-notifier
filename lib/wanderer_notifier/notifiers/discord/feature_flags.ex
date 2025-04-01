defmodule WandererNotifier.Notifiers.Discord.FeatureFlags do
  @moduledoc """
  Manages feature flags for Discord API functionality.
  Allows for gradual rollout of new Discord features.
  """

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Checks if message components are enabled.
  Components include buttons, select menus, etc.

  ## Returns
    - true if components are enabled
    - false otherwise
  """
  def components_enabled? do
    get_feature_flag(:discord_components_enabled, true)
  end

  @doc """
  Checks if versioned API endpoints are enabled.

  ## Returns
    - true if versioned API is enabled
    - false otherwise
  """
  def versioned_api_enabled? do
    get_feature_flag(:discord_versioned_api_enabled, true)
  end

  @doc """
  Gets the value of a feature flag, with a default fallback.

  ## Parameters
    - flag_name: The name of the feature flag
    - default: Default value if flag is not set

  ## Returns
    - The value of the feature flag, or the default if not set
  """
  def get_feature_flag(flag_name, default) do
    flag_value = Features.get_feature(flag_name)

    case flag_value do
      nil ->
        default

      value when is_boolean(value) ->
        value

      "true" ->
        true

      "false" ->
        false

      other ->
        AppLogger.config_warn("Invalid feature flag value",
          flag: flag_name,
          value: other,
          using_default: default
        )

        default
    end
  end
end
