defmodule WandererNotifier.Domains.Notifications.Discord.EnrichmentHelper do
  @moduledoc """
  Helper module for enriching notification data with additional context.

  Centralizes system name enrichment logic for killmail and rally point notifications.
  """

  alias WandererNotifier.Domains.Killmail.{Killmail, Enrichment}
  alias WandererNotifier.Domains.Tracking.Entities.System, as: TrackedSystem

  @doc """
  Enriches a killmail with the custom system name from tracked systems if available.

  Falls back to ESI system name if not tracked or no custom name exists.
  """
  def enrich_killmail_with_system_name(%Killmail{} = killmail) do
    case get_system_id(killmail) do
      id when is_integer(id) ->
        system_name = get_tracked_system_name(id) || Enrichment.get_system_name(id)
        %{killmail | system_name: system_name}

      _ ->
        killmail
    end
  end

  @doc """
  Enriches a rally point with the custom system name from tracked systems if available.

  Converts structs to maps to ensure Map.put/3 works correctly.
  """
  def enrich_rally_with_system_name(rally_point) do
    rally_map = normalize_to_map(rally_point)
    system_id = rally_map[:system_id]

    case system_id do
      id when is_integer(id) ->
        case get_tracked_system_name(id) do
          nil -> rally_map
          custom_name -> Map.put(rally_map, :system_name, custom_name)
        end

      _ ->
        rally_map
    end
  end

  @doc """
  Gets the custom name for a tracked system by its ID.

  Returns nil if the system is not tracked or has no custom name.
  """
  def get_tracked_system_name(system_id) when is_integer(system_id) do
    system_id
    |> Integer.to_string()
    |> TrackedSystem.get_system()
    |> case do
      {:ok, %{name: name}} when is_binary(name) -> name
      _ -> nil
    end
  end

  def get_tracked_system_name(_), do: nil

  # Private helpers

  defp get_system_id(%Killmail{system_id: system_id}) when is_integer(system_id), do: system_id
  defp get_system_id(_), do: nil

  defp normalize_to_map(data) when is_struct(data), do: Map.from_struct(data)
  defp normalize_to_map(data) when is_map(data), do: data
  defp normalize_to_map(_), do: %{}
end
