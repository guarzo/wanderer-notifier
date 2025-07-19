defmodule WandererNotifier.Shared.Config.Diagnostics do
  @moduledoc """
  Configuration diagnostic utilities shared across config modules.
  """

  alias WandererNotifier.Shared.Config.Utils

  @doc """
  Returns a diagnostic map of all map-related configuration.
  Useful for troubleshooting map API issues.
  """
  def map_config_diagnostics(config_module) do
    token = config_module.map_token()
    base_url = config_module.map_url()
    name = config_module.map_name()

    %{
      map_url: base_url,
      map_url_present: base_url |> Utils.nil_or_empty?() |> Kernel.not(),
      map_url_explicit: config_module.get(:map_url) |> Utils.nil_or_empty?() |> Kernel.not(),
      map_name: name,
      map_name_present: name |> Utils.nil_or_empty?() |> Kernel.not(),
      map_name_explicit: config_module.get(:map_name) |> Utils.nil_or_empty?() |> Kernel.not(),
      map_token: token,
      map_token_present: !Utils.nil_or_empty?(token),
      map_token_length: if(token, do: String.length(token), else: 0),
      map_slug: config_module.map_slug(),
      map_slug_present: !Utils.nil_or_empty?(config_module.map_slug()),
      base_map_url: config_module.base_map_url(),
      base_map_url_present: !Utils.nil_or_empty?(config_module.base_map_url()),
      system_tracking_enabled: config_module.system_tracking_enabled?()
    }
  end
end
