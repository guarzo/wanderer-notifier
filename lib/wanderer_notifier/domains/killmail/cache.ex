defmodule WandererNotifier.Domains.Killmail.Cache do
  @moduledoc """
  Provides caching utilities for killmail-related data.

  This module was previously responsible for ZKillboard killmail caching, but with
  the migration to WebSocket with pre-enriched data, it now only handles system
  name caching for the pipeline.
  """

  alias WandererNotifier.Infrastructure.Cache

  @doc """
  Gets a system name from the cache or from the API.

  ## Parameters
  - system_id: The ID of the system to get name for

  ## Returns
  - System name string or "System [ID]" if not found
  """
  def get_system_name(nil), do: "Unknown"

  def get_system_name(system_id) when is_integer(system_id) do
    # Use the simplified cache directly
    cache_key = "esi:system_name:#{system_id}"

    case Cache.get(cache_key) do
      {:ok, name} when is_binary(name) ->
        name

      _ ->
        # No cached name, fetch from ESI
        case esi_service().get_system(system_id, []) do
          {:ok, %{"name" => name}} when is_binary(name) ->
            # Cache the name with 1 hour TTL
            Cache.put(cache_key, name, :timer.hours(1))
            name

          _ ->
            "System #{system_id}"
        end
    end
  end

  def get_system_name(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, ""} -> get_system_name(id)
      _ -> "System #{system_id}"
    end
  end

  # Dependency injection helper
  defp esi_service,
    do:
      Application.get_env(
        :wanderer_notifier,
        :esi_service,
        WandererNotifier.Infrastructure.Adapters.ESI.Service
      )
end
