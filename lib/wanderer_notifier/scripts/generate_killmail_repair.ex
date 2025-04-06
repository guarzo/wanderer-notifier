defmodule WandererNotifier.Scripts.GenerateKillmailRepair do
  @moduledoc """
  Generates a repair script for killmail records with missing or incomplete data.
  Use this to create a script that can repair all existing killmail records.
  """

  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Logger.Logger, as: AppLogger

  require Ash.Query

  @doc """
  Generates a repair script for killmail records with missing region data.
  This will not actually fix the records but will create a script that can be run later.

  ## Parameters
    - path: The path to save the repair script to
    - limit: Maximum number of records to process (default: nil, meaning all records)

  ## Returns
    - {:ok, path} on success
    - {:error, reason} on failure
  """
  def generate_region_repair_script(path, limit \\ nil) do
    # Find killmails with missing region data
    query =
      Killmail
      |> Ash.Query.filter(is_nil(region_name) or region_name == "")
      |> Ash.Query.sort(kill_time: :desc)

    # Apply limit if provided
    query = if limit, do: Ash.Query.limit(query, limit), else: query

    # Execute the query
    case Api.read(query) do
      {:ok, killmails} when is_list(killmails) ->
        # Generate the repair script content
        script_content = """
        # Generated Killmail Repair Script
        # Run this script to fix killmail records with missing region data
        # Generated on: #{DateTime.utc_now()}

        defmodule WandererNotifier.Scripts.KillmailRepair do
          alias WandererNotifier.Resources.Killmail
          alias WandererNotifier.Resources.Api
          alias WandererNotifier.Api.ESI.Service, as: ESIService

          def run do
            IO.puts("Starting killmail repair...")

            #{generate_repair_functions()}

            records_to_fix = [
              #{generate_record_list(killmails)}
            ]

            IO.puts("Found \#{length(records_to_fix)} records to fix")

            Enum.each(records_to_fix, fn record_id ->
              fix_record(record_id)
            end)

            IO.puts("Repair complete!")
          end
        end

        # To run this script:
        # 1. Save this file
        # 2. Execute with mix:
        #    mix run path/to/this/script.exs
        """

        # Write to the specified path
        case File.write(path, script_content) do
          :ok ->
            AppLogger.info("Successfully generated repair script",
              path: path,
              count: length(killmails)
            )

            {:ok, path}

          {:error, reason} ->
            AppLogger.error("Failed to write repair script", path: path, error: reason)
            {:error, reason}
        end

      {:ok, _} ->
        AppLogger.info("No killmails with missing region data found")
        {:ok, path}

      error ->
        AppLogger.error("Error finding killmails with missing region data", error: inspect(error))
        {:error, error}
    end
  end

  # Generate the repair functions for the script
  defp generate_repair_functions do
    """
    def fix_record(id) do
      case Api.get(Killmail, id) do
        {:ok, killmail} ->
          fix_missing_region(killmail)

        {:error, error} ->
          IO.puts("Error fetching killmail \#{id}: \#{inspect(error)}")
      end
    end

    def fix_missing_region(killmail) do
      if is_nil(killmail.region_name) or killmail.region_name == "" do
        # Try to get system info which includes constellation (which includes region)
        IO.puts("Fixing region for killmail \#{killmail.id} (ID: \#{killmail.killmail_id})")

        system_id = killmail.solar_system_id

        if system_id do
          case ESIService.get_system_info(system_id) do
            {:ok, system_info} ->
              # Extract constellation ID from system info
              constellation_id = Map.get(system_info, "constellation_id")

              if constellation_id do
                # Get constellation info to find region
                case ESIService.get_constellation_info(constellation_id) do
                  {:ok, constellation_info} ->
                    region_id = Map.get(constellation_info, "region_id")

                    if region_id do
                      # Get region name
                      case ESIService.get_region_name(region_id) do
                        {:ok, region_info} ->
                          region_name = Map.get(region_info, "name", "Unknown Region")

                          # Update the killmail
                          update_killmail_region(killmail, region_id, region_name)

                        _ ->
                          # Could find region ID but not name
                          region_name = handle_wormhole_region(system_id)
                          update_killmail_region(killmail, region_id, region_name)
                      end
                    else
                      # Fallback for wormhole systems which may not have standard regions
                      region_name = handle_wormhole_region(system_id)
                      update_killmail_region(killmail, nil, region_name)
                    end

                  _ ->
                    # Could not get constellation info
                    region_name = handle_wormhole_region(system_id)
                    update_killmail_region(killmail, nil, region_name)
                end
              else
                # No constellation ID found
                region_name = handle_wormhole_region(system_id)
                update_killmail_region(killmail, nil, region_name)
              end

            _ ->
              # Could not get system info
              region_name = handle_wormhole_region(system_id)
              update_killmail_region(killmail, nil, region_name)
          end
        else
          IO.puts("No system ID for killmail \#{killmail.id}, cannot fix region.")
        end
      end
    end

    def update_killmail_region(killmail, region_id, region_name) do
      IO.puts("Updating killmail \#{killmail.id} with region_id=\#{region_id || "nil"}, region_name=\#{region_name}")

      case Api.update(Killmail, killmail.id,
        region_id: region_id,
        region_name: region_name
      ) do
        {:ok, _updated} ->
          IO.puts("Successfully updated killmail \#{killmail.id}")

        {:error, error} ->
          IO.puts("Error updating killmail \#{killmail.id}: \#{inspect(error)}")
      end
    end

    def handle_wormhole_region(system_id) when is_integer(system_id) do
      # Higher ranges are typically wormhole systems
      if system_id > 31_000_000 do
        "J-Space"
      else
        "Unknown Region"
      end
    end

    def handle_wormhole_region(_), do: "Unknown Region"
    """
  end

  # Generate the list of record IDs for the script
  defp generate_record_list(killmails) do
    killmails
    |> Enum.map(fn killmail -> "\"#{killmail.id}\"" end)
    |> Enum.join(",\n      ")
  end
end
