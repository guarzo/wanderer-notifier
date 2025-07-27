defmodule WandererNotifier.Domains.Killmail.Enrichment do
  @moduledoc """
  Handles fetching recent kills via WandererKills API for system notifications
  and provides caching utilities for killmail-related data.

  This module was previously responsible for ESI enrichment, but with the migration
  to WebSocket with pre-enriched data, it now handles recent kills lookup and
  system name caching (merged from Killmail.Cache).
  """

  alias WandererNotifier.Infrastructure.{Http, Cache}
  alias WandererNotifier.Shared.Utils.ErrorHandler
  require Logger

  @doc """
  Fetches and formats the latest kills for a system (default 3).
  """
  @spec recent_kills_for_system(integer(), non_neg_integer()) :: String.t()
  def recent_kills_for_system(system_id, limit \\ 3) do
    ErrorHandler.safe_execute_string(
      fn ->
        case get_system_kills(system_id, limit) do
          {:ok, kills} when is_list(kills) and length(kills) > 0 ->
            kills
            |> Enum.map(&format_wanderer_kill/1)
            |> Enum.join("\n")

          {:ok, []} ->
            "No recent kills found"

          {:error, _reason} ->
            "Error retrieving kill data"

          _resp ->
            "Unexpected kill data response"
        end
      end,
      fallback: "Error retrieving kill data",
      context: %{system_id: system_id, limit: limit}
    )
  end

  @doc """
  Gets a system name from the cache or from the API.
  Merged from WandererNotifier.Domains.Killmail.Cache.

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

  # --- Private Functions ---

  @spec get_system_kills(integer(), non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  defp get_system_kills(system_id, limit) do
    base_url =
      Application.get_env(
        :wanderer_notifier,
        :wanderer_kills_base_url,
        "http://host.docker.internal:4004"
      )

    url = "#{base_url}/api/v1/kills/system/#{system_id}?limit=#{limit}&since_hours=168"

    case Http.request(:get, url, nil, [], []) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Format a kill from WandererKills API
  defp format_wanderer_kill(kill) do
    ErrorHandler.safe_execute_string(
      fn ->
        killmail_id = Map.get(kill, "killmail_id", "Unknown")
        victim_name = get_in(kill, ["victim", "character_name"]) || "Unknown"
        ship_name = get_in(kill, ["victim", "ship_name"]) || "Unknown Ship"
        value = Map.get(kill, "total_value", 0)

        # Format relative time
        time_str =
          case Map.get(kill, "kill_time") do
            nil -> ""
            time -> format_kill_time(time)
          end

        "[#{ship_name} (#{format_isk_value(value)})](https://zkillboard.com/kill/#{killmail_id}/) - #{victim_name} #{time_str}"
      end,
      fallback: "Unknown kill",
      context: %{kill_data: kill}
    )
  end

  defp format_kill_time(time_str) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _} ->
        diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)
        format_time_diff(diff_seconds)

      _ ->
        ""
    end
  end

  defp format_kill_time(_), do: ""

  defp format_time_diff(sec) when sec < 60, do: "(just now)"
  defp format_time_diff(sec) when sec < 3_600, do: "(#{div(sec, 60)}m ago)"
  defp format_time_diff(sec) when sec < 86_400, do: "(#{div(sec, 3_600)}h ago)"
  defp format_time_diff(sec), do: "(#{div(sec, 86_400)}d ago)"

  defp format_isk_value(v) when is_number(v) do
    cond do
      v >= 1_000_000_000 -> "#{Float.round(v / 1_000_000_000, 1)}B ISK"
      v >= 1_000_000 -> "#{Float.round(v / 1_000_000, 1)}M ISK"
      v >= 1_000 -> "#{Float.round(v / 1_000, 1)}K ISK"
      true -> "#{trunc(v)} ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

  # Dependency injection helper (merged from Cache module)
  defp esi_service,
    do:
      Application.get_env(
        :wanderer_notifier,
        :esi_service,
        WandererNotifier.Infrastructure.Adapters.ESI.Service
      )
end
