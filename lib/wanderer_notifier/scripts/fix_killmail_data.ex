defmodule WandererNotifier.Scripts.FixKillmailData do
  @moduledoc """
  Script to fix data issues in stored killmail records.

  Usage:
    - Run with `mix run -e 'WandererNotifier.Scripts.FixKillmailData.fix_missing_regions()'`
    - Run with `mix run -e 'WandererNotifier.Scripts.FixKillmailData.fix_missing_data()'` for all data issues
  """

  import Ecto.Query

  require Ash.Query
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Data.Repo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail

  @batch_size 50
  # Set a safety limit to avoid unintended large changes
  @max_records 1000

  @doc """
  Fixes missing region data in killmail records.
  Looks for records with solar_system_id but no region_id or region_name,
  then fetches the system info from ESI and updates the records.
  """
  def fix_missing_regions do
    count_missing = count_killmails_with_missing_regions()

    if count_missing > 0 do
      AppLogger.info("Found #{count_missing} killmail records with missing regions")

      count_to_process = min(count_missing, @max_records)

      AppLogger.info(
        "Will process up to #{count_to_process} records in batches of #{@batch_size}"
      )

      # Process in batches
      process_missing_regions(count_to_process)

      AppLogger.info("Completed processing missing region data")
    else
      AppLogger.info("No killmail records with missing region data found")
    end
  end

  @doc """
  Fixes all identified data issues in killmail records.
  Currently includes:
  - Missing region data
  - Future versions may add more data fixes
  """
  def fix_missing_data do
    # Fix missing regions
    fix_missing_regions()

    # In the future, add more data fixes here

    AppLogger.info("Completed fixing all identified data issues")
  end

  # Count killmails with missing region data
  defp count_killmails_with_missing_regions do
    query =
      Ash.Query.filter(
        Killmail,
        not is_nil(solar_system_id) and
          (is_nil(region_id) or is_nil(region_name) or region_name == "Unknown Region")
      )

    case Api.read(query, page: [count: :only]) do
      {:ok, count} -> count
      {:error, _reason} -> 0
    end
  end

  # Process records with missing region data in batches
  defp process_missing_regions(total_count) do
    stream_killmails_with_missing_regions()
    |> Stream.take(total_count)
    |> Stream.chunk_every(@batch_size)
    |> Stream.with_index()
    |> Stream.each(fn {batch, idx} ->
      process_batch(batch, idx)
    end)
    |> Stream.run()
  end

  # Process a batch of killmails to update their region data
  defp process_batch(killmails, batch_index) do
    AppLogger.info("Processing batch #{batch_index + 1} with #{length(killmails)} records")

    results =
      killmails
      |> Enum.map(&fetch_and_update_region/1)
      |> Enum.reject(&is_nil/1)

    success_count = Enum.count(results, fn {status, _} -> status == :ok end)
    error_count = Enum.count(results, fn {status, _} -> status == :error end)

    AppLogger.info(
      "Batch #{batch_index + 1} complete: #{success_count} updated, #{error_count} failed"
    )
  end

  # Stream killmails with missing region data
  defp stream_killmails_with_missing_regions do
    query =
      from(k in "killmails",
        where:
          not is_nil(k.solar_system_id) and
            (is_nil(k.region_id) or is_nil(k.region_name) or k.region_name == "Unknown Region"),
        select: %{id: k.id, killmail_id: k.killmail_id, solar_system_id: k.solar_system_id}
      )

    Repo.stream(query)
  end

  # Fetch region data for a system and update the killmail
  defp fetch_and_update_region(%{id: id, killmail_id: killmail_id, solar_system_id: system_id}) do
    case ESIService.get_system_info(system_id) do
      {:ok, system_info} ->
        # Extract region data from system info
        region_id = system_info["constellation"]["region_id"]

        # Get region name if region_id is available
        region_name =
          if region_id do
            case ESIService.get_region(region_id) do
              {:ok, region_info} -> region_info["name"]
              _ -> handle_wormhole_region(system_id)
            end
          else
            handle_wormhole_region(system_id)
          end

        # Update the killmail with the region info
        update_killmail_region(id, region_id, region_name, killmail_id)

      {:error, reason} ->
        AppLogger.error("Failed to fetch system info for system_id: #{system_id}",
          error: inspect(reason),
          killmail_id: killmail_id
        )

        {:error, "Failed to fetch system info"}
    end
  end

  # For wormhole systems that don't have regions in ESI
  defp handle_wormhole_region(system_id) when is_integer(system_id) do
    # Wormhole systems conventionally all belong to "J-Space" region
    # And their names often start with J
    "J-Space"
  end

  defp handle_wormhole_region(_), do: "Unknown Region"

  # Update a killmail with region information
  defp update_killmail_region(id, region_id, region_name, killmail_id) do
    case Api.get(Killmail, id) do
      {:ok, killmail} ->
        changes = %{
          region_id: region_id,
          region_name: region_name
        }

        case Api.update(killmail, changes) do
          {:ok, updated} ->
            AppLogger.info("Updated killmail #{killmail_id} with region: #{region_name}")
            {:ok, updated}

          {:error, reason} ->
            AppLogger.error("Failed to update killmail #{killmail_id}", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.error("Failed to get killmail with id: #{id}", error: inspect(reason))
        {:error, reason}
    end
  end
end
