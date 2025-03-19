defmodule WandererNotifier.CorpTools.ChartService do
  @moduledoc """
  Unified service for chart generation and delivery.

  This module provides a central point for all chart-related functionality,
  generating charts server-side using Node.js and Chart.js.

  ## Examples

  ```elixir
  # Create a chart config
  {:ok, config} = ChartConfig.new(%{
    type: ChartTypes.damage_final_blows(),
    title: "Damage and Final Blows",
    data: player_data
  })

  # Generate chart
  {:ok, chart_path} = ChartService.generate_chart(config)

  # Or generate and send in one operation
  {:ok, _} = ChartService.generate_and_send(config, "Chart Title", "Chart Description")
  ```
  """
  require Logger

  alias WandererNotifier.CorpTools.ChartConfig
  alias WandererNotifier.CorpTools.ChartTypes

  # Define paths
  @script_path Path.join(:code.priv_dir(:wanderer_notifier), "charts/simple_renderer.js")
  @temp_dir Path.join(:code.priv_dir(:wanderer_notifier), "temp")
  @charts_dir Path.join(:code.priv_dir(:wanderer_notifier), "static/images/charts")

  @doc """
  Initializes the chart service, ensuring directories exist and dependencies are installed.
  """
  def init do
    # Ensure temp directory exists
    File.mkdir_p!(@temp_dir)

    # Ensure charts directory exists
    File.mkdir_p!(@charts_dir)

    # Log script path for debugging
    Logger.info("Chart renderer script path: #{@script_path}")

    # Check if Node.js dependencies are installed
    charts_dir = Path.join(:code.priv_dir(:wanderer_notifier), "charts")
    node_modules_path = Path.join(charts_dir, "node_modules")

    if !File.exists?(node_modules_path) do
      Logger.info("Installing Node.js dependencies for chart generation...")

      case System.cmd("npm", ["install"], cd: charts_dir) do
        {output, 0} ->
          Logger.info("Successfully installed Node.js dependencies")
          {:ok, output}

        {output, status} ->
          Logger.error(
            "Failed to install Node.js dependencies. Status: #{status}, Output: #{output}"
          )

          {:error, "Failed to install Node.js dependencies"}
      end
    else
      Logger.info("Node.js dependencies already installed")
      :ok
    end
  end

  @doc """
  Generates a chart using a ChartConfig struct.

  Args:
    - config: A ChartConfig struct

  Returns:
    - {:ok, chart_path} on success
    - {:error, reason} on failure
  """
  @spec generate_chart(ChartConfig.t()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_chart(%ChartConfig{} = config) do
    Logger.info("Generating chart with type: #{config.type}, title: #{config.title}")

    # Generate the chart
    generate_chart_internal(config.type, ChartConfig.to_json(config))
  end

  @doc """
  Legacy interface - generates a chart of the specified type with the provided data.
  This method maintains backward compatibility with the old interface.

  Args:
    - chart_type: The chart type (atom or string)
    - data: The data for the chart

  Returns:
    - {:ok, chart_path} on success
    - {:error, reason} on failure
  """
  @spec generate_chart(atom() | String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_chart(chart_type, data) when is_atom(chart_type) and is_map(data) do
    # Convert atom to string using the new ChartTypes module
    chart_type_str = apply(ChartTypes, chart_type, [])

    if chart_type_str == nil do
      {:error, "Unknown chart type: #{chart_type}"}
    else
      generate_chart(chart_type_str, data)
    end
  end

  def generate_chart(chart_type, data) when is_binary(chart_type) and is_map(data) do
    # Check if the chart type is valid
    if !ChartTypes.valid?(chart_type) do
      Logger.warning("Potentially invalid chart type: #{chart_type}")
    end

    # Extract chart data from the legacy format
    Logger.info("Using legacy format for chart generation: #{chart_type}")

    # For backward compatibility, try to create chart config from legacy data
    case extract_legacy_chart_data(chart_type, data) do
      {:ok, config} ->
        # Generate using the new method
        generate_chart(config)

      {:error, reason} ->
        # Fallback to direct generation if we can't extract properly
        Logger.warning("Using direct generation due to error: #{reason}")
        generate_chart_internal(chart_type, data)
    end
  end

  # Extracts chart data from legacy format
  @spec extract_legacy_chart_data(String.t(), map()) ::
          {:ok, ChartConfig.t()} | {:error, String.t()}
  defp extract_legacy_chart_data(chart_type, data) do
    try do
      # Special case for TPS data which may have a different structure
      case handle_tps_format(data, chart_type) do
        {:ok, config} ->
          {:ok, config}

        {:error, _reason} ->
          # Regular approach - try to extract the time frame and chart data
          time_frames = Map.get(data, "TimeFrames")

          if time_frames && is_map(time_frames) do
            # Get the first time frame
            [time_frame_key | _] = Map.keys(time_frames)
            time_frame = Map.get(time_frames, time_frame_key)

            if time_frame && is_map(time_frame) do
              charts = Map.get(time_frame, "Charts")

              if charts && is_map(charts) do
                # Find the matching chart by type or ID
                chart = find_chart_by_type(charts, chart_type)

                if chart && is_map(chart) do
                  # Extract chart data
                  chart_data =
                    case Map.get(chart, "Data") do
                      data when is_binary(data) ->
                        Jason.decode!(data)

                      data ->
                        data
                    end

                  # Create a config
                  ChartConfig.new(%{
                    type: chart_type,
                    title:
                      Map.get(chart, "name") || Map.get(chart, "Name") ||
                        ChartTypes.display_name(chart_type),
                    data: chart_data,
                    id:
                      Map.get(chart, "id") || Map.get(chart, "ID") ||
                        "chart_#{:rand.uniform(1000)}"
                  })
                else
                  {:error, "Chart not found for type: #{chart_type}"}
                end
              else
                {:error, "No Charts found in time frame"}
              end
            else
              {:error, "Invalid time frame structure"}
            end
          else
            # Try direct data access as fallback
            {:error, "No TimeFrames structure found"}
          end
      end
    rescue
      e ->
        Logger.error("Error extracting legacy chart data: #{inspect(e)}")
        {:error, "Error extracting legacy chart data: #{Exception.message(e)}"}
    end
  end

  # Special handler for TPS data format which may differ from the standard TimeFrames structure
  defp handle_tps_format(data, chart_type) do
    Logger.debug("Attempting to handle TPS data format for chart type: #{chart_type}")

    # Check if this is TPS data based on common keys
    is_tps_data =
      is_map(data) &&
        (Map.has_key?(data, "Last12MonthsData") ||
           Map.has_key?(data, "Last30DaysData") ||
           Map.has_key?(data, "KillsByShipType"))

    if is_tps_data do
      Logger.info("Detected TPS data format")
      # Log the structure to help with debugging
      Logger.debug("TPS data keys: #{inspect(Map.keys(data))}")

      if Map.has_key?(data, "Last30DaysData") do
        Logger.debug("Last30DaysData keys: #{inspect(Map.keys(data["Last30DaysData"]))}")
      end

      case chart_type do
        "damage_final_blows" ->
          # For damage charts, we might need to extract from a specific location
          damage_data = get_damage_data_from_tps(data)
          Logger.info("Extracted #{length(damage_data)} player records from TPS data")

          if damage_data != [] do
            {:ok, config} =
              ChartConfig.new(%{
                type: chart_type,
                title: "Damage and Final Blows",
                data: damage_data
              })

            {:ok, config}
          else
            # If we couldn't find damage data, return an empty array that the renderer can handle
            Logger.warning("No damage data found in TPS data, creating empty chart")

            {:ok, config} =
              ChartConfig.new(%{
                type: chart_type,
                title: "Damage and Final Blows (No Data)",
                data: []
              })

            {:ok, config}
          end

        "kills_by_ship_type" ->
          ship_type_data = get_in(data, ["Last12MonthsData", "KillsByShipType"])

          if is_map(ship_type_data) && map_size(ship_type_data) > 0 do
            # Convert map to array of objects for the chart
            formatted_data =
              ship_type_data
              |> Enum.map(fn {ship_type, count} ->
                %{"ship_type" => ship_type, "kills" => count, "isk_destroyed" => 0}
              end)
              |> Enum.sort_by(fn %{"kills" => kills} -> kills end, :desc)
              |> Enum.take(10)

            {:ok, config} =
              ChartConfig.new(%{
                type: chart_type,
                title: "Kills by Ship Type",
                data: formatted_data
              })

            {:ok, config}
          else
            # Return empty config for proper error handling
            {:ok, config} =
              ChartConfig.new(%{
                type: chart_type,
                title: "Kills by Ship Type (No Data)",
                data: []
              })

            {:ok, config}
          end

        "kills_by_month" ->
          kills_data = get_in(data, ["Last12MonthsData", "KillsByMonth"])

          if is_map(kills_data) && map_size(kills_data) > 0 do
            # Convert map to array format
            formatted_data =
              kills_data
              |> Enum.map(fn {month, kills} ->
                %{"Time" => month, "Kills" => kills}
              end)
              |> Enum.sort_by(fn %{"Time" => time} -> time end)

            {:ok, config} =
              ChartConfig.new(%{
                type: "kill_activity_over_time",
                title: "Kills by Month",
                data: formatted_data
              })

            {:ok, config}
          else
            # Return empty config for proper error handling
            {:ok, config} =
              ChartConfig.new(%{
                type: "kill_activity_over_time",
                title: "Kills by Month (No Data)",
                data: []
              })

            {:ok, config}
          end

        _ ->
          {:error, "Unsupported TPS chart type: #{chart_type}"}
      end
    else
      {:error, "Not TPS data format"}
    end
  end

  # Extract damage data from TPS data structure
  defp get_damage_data_from_tps(data) do
    # Check different possible locations for damage data
    results =
      cond do
        # Look for DamageByPlayer in last 30 days first
        damage_by_player = get_in(data, ["Last30DaysData", "DamageByPlayer"]) ->
          if is_map(damage_by_player) && map_size(damage_by_player) > 0 do
            # Convert to array format with name, damage and final blows
            Logger.info("Found DamageByPlayer data with #{map_size(damage_by_player)} entries")

            damage_by_player
            |> Enum.map(fn {player, stats} ->
              final_blows = get_in(stats, ["FinalBlows"]) || 0
              damage_done = get_in(stats, ["DamageDone"]) || 0
              %{"Name" => player, "DamageDone" => damage_done, "FinalBlows" => final_blows}
            end)
            |> Enum.sort_by(fn %{"DamageDone" => damage} -> damage end, :desc)
            |> Enum.take(20)
          else
            Logger.warning("DamageByPlayer exists but is empty or invalid")
            []
          end

        # Look for PlayerData in monthly data
        player_data = get_in(data, ["Last30DaysData", "PlayerData"]) ->
          if is_list(player_data) && length(player_data) > 0 do
            Logger.info("Found PlayerData array with #{length(player_data)} entries")

            player_data
            |> Enum.map(fn player ->
              %{
                "Name" => Map.get(player, "Name") || "Unknown",
                "DamageDone" => Map.get(player, "DamageDone") || 0,
                "FinalBlows" => Map.get(player, "FinalBlows") || 0
              }
            end)
            |> Enum.sort_by(fn %{"DamageDone" => damage} -> damage end, :desc)
            |> Enum.take(20)
          else
            Logger.warning("PlayerData exists but is empty or invalid")
            []
          end

        # Try to extract directly from data if it has the right keys
        is_list(data) && length(data) > 0 &&
            Enum.all?(data, fn item ->
              is_map(item) && (Map.has_key?(item, "DamageDone") || Map.has_key?(item, "Name"))
            end) ->
          Logger.info("Using direct data which appears to be in the correct format already")

          data
          |> Enum.map(fn item ->
            %{
              "Name" => Map.get(item, "Name") || "Unknown",
              "DamageDone" => Map.get(item, "DamageDone") || 0,
              "FinalBlows" => Map.get(item, "FinalBlows") || 0
            }
          end)
          |> Enum.sort_by(fn %{"DamageDone" => damage} -> damage end, :desc)
          |> Enum.take(20)

        # No damage data found
        true ->
          Logger.warning("No damage data found in TPS data structure")
          []
      end

    # Ensure all entries have the expected format
    results
    |> Enum.map(fn item ->
      %{
        "Name" => Map.get(item, "Name") || "Unknown",
        "DamageDone" => Map.get(item, "DamageDone") || 0,
        "FinalBlows" => Map.get(item, "FinalBlows") || 0
      }
    end)
  end

  # Finds a chart by type in the charts map
  @spec find_chart_by_type(map(), String.t()) :: map() | nil
  defp find_chart_by_type(charts, chart_type) do
    # First try to find directly by key
    direct_match = Map.get(charts, chart_type)

    if direct_match do
      direct_match
    else
      # Try to find by ID or id field
      Enum.find_value(charts, fn {_, chart} ->
        id = Map.get(chart, "ID") || Map.get(chart, "id")
        if id == chart_type, do: chart, else: nil
      end)
    end
  end

  # Internal implementation of chart generation
  @spec generate_chart_internal(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  defp generate_chart_internal(chart_type, data) do
    # Write data to temp file
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    data_file = Path.join(@temp_dir, "chart_data_#{timestamp}.json")
    output_file = Path.join(@charts_dir, "chart_#{chart_type}_#{timestamp}.png")

    # Ensure JSON data is properly formatted
    case Jason.encode(data) do
      {:ok, json_data} ->
        # Write data to temp file
        File.write!(data_file, json_data)

        # Call Node.js script to generate chart using the simple renderer
        result = System.cmd("node", [@script_path, data_file, output_file])

        case result do
          {_, 0} ->
            # If command succeeded and file exists, consider it a success
            if File.exists?(output_file) do
              Logger.info("Chart generated successfully at #{output_file}")
              # Clean up temp file
              File.rm(data_file)
              {:ok, output_file}
            else
              Logger.error("Command succeeded but output file not found")
              {:error, "Output file not found"}
            end

          {output, status} ->
            Logger.error("Chart generation failed with status #{status}: #{output}")

            # Even if the command failed, check if the file was created
            if File.exists?(output_file) do
              Logger.warning("Command failed but output file exists, using it anyway")
              # Clean up temp file
              File.rm(data_file)
              {:ok, output_file}
            else
              {:error, "Chart generation failed with status #{status}"}
            end
        end

      {:error, reason} ->
        Logger.error("Failed to encode chart data to JSON: #{inspect(reason)}")
        {:error, "Failed to encode chart data to JSON"}
    end
  end

  @doc """
  Sends a chart to Discord with the given title and description.

  Args:
    - chart_path: Path to the chart image
    - title: Title for the Discord embed
    - description: Description for the Discord embed

  Returns:
    - :ok on success
    - {:error, reason} on failure
  """
  @spec send_chart_to_discord(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def send_chart_to_discord(chart_path, title, description) do
    Logger.info("Sending chart to Discord: #{title}")

    # Read the chart file
    case File.read(chart_path) do
      {:ok, image_data} ->
        # Get the appropriate notifier
        notifier = WandererNotifier.NotifierFactory.get_notifier()

        # Send the file with title and description
        # The notifier expects (filename, data, title, description)
        filename = Path.basename(chart_path)
        notifier.send_file(filename, image_data, title, description)

      {:error, reason} ->
        Logger.error("Failed to read chart file: #{inspect(reason)}")
        {:error, "Failed to read chart file: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates a chart using a config and sends it to Discord in one operation.

  Args:
    - config: The ChartConfig struct
    - title: Title for the Discord embed (optional, uses config.title if not provided)
    - description: Description for the Discord embed (optional)

  Returns:
    - {:ok, chart_path} on success
    - {:error, reason} on failure
  """
  @spec generate_and_send(ChartConfig.t(), String.t() | nil, String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_and_send(%ChartConfig{} = config, title \\ nil, description \\ nil) do
    # Use config title if no title provided
    discord_title = title || config.title
    discord_desc = description || ""

    case generate_chart(config) do
      {:ok, chart_path} ->
        case send_chart_to_discord(chart_path, discord_title, discord_desc) do
          :ok -> {:ok, chart_path}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Legacy interface - generates a chart and sends it to Discord in one operation.

  Args:
    - chart_type: The type of chart to generate
    - data: The data for the chart
    - title: Title for the Discord embed
    - description: Description for the Discord embed

  Returns:
    - {:ok, chart_path} on success
    - {:error, reason} on failure
  """
  @spec generate_and_send_chart(atom() | String.t(), map(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_and_send_chart(chart_type, data, title, description) do
    case generate_chart(chart_type, data) do
      {:ok, chart_path} ->
        case send_chart_to_discord(chart_path, title, description) do
          :ok -> {:ok, chart_path}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Deletes old chart files to prevent disk space issues.
  Only keeps charts from the last 24 hours.
  """
  @spec cleanup_old_charts() :: :ok
  def cleanup_old_charts do
    Logger.info("Cleaning up old chart files...")

    # Get all PNG files in the charts directory
    case File.ls(@charts_dir) do
      {:ok, files} ->
        png_files = Enum.filter(files, &String.ends_with?(&1, ".png"))

        # Calculate cutoff time (24 hours ago)
        one_day_ago = DateTime.utc_now() |> DateTime.add(-86400, :second)

        # Delete files older than cutoff
        Enum.each(png_files, fn file ->
          file_path = Path.join(@charts_dir, file)

          case File.stat(file_path, time: :posix) do
            {:ok, %{mtime: mtime}} ->
              file_time = DateTime.from_unix!(mtime)

              if DateTime.compare(file_time, one_day_ago) == :lt do
                Logger.debug("Deleting old chart file: #{file}")
                File.rm(file_path)
              end

            {:error, reason} ->
              Logger.warning("Could not get file stats for #{file}: #{inspect(reason)}")
          end
        end)

      {:error, reason} ->
        Logger.error("Error listing chart files: #{inspect(reason)}")
    end

    :ok
  end
end
