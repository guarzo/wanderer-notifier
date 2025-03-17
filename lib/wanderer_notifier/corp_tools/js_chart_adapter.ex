defmodule WandererNotifier.CorpTools.JSChartAdapter do
  @moduledoc """
  Adapter for generating charts using JavaScript chart configurations.

  This adapter is responsible for generating charts based on JavaScript chart configurations
  stored in the priv/charts directory. It is different from the TPSChartAdapter which
  generates charts directly using the QuickChart API without JavaScript configurations.
  """
  require Logger
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient

  @quickcharts_url "https://quickchart.io/chart"
  @chart_width 800
  @chart_height 400
  @chart_background_color "rgb(47, 49, 54)"  # Discord dark theme background
  @chart_text_color "rgb(255, 255, 255)"     # White text for Discord dark theme

  @doc """
  Generates a chart URL for damage and final blows.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_damage_final_blows_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract character performance data from TPS data
        character_performance_data = extract_character_performance_data(data)

        if is_list(character_performance_data) and length(character_performance_data) > 0 do
          # Sort by damage done (descending) and take top 20
          sorted_data =
            character_performance_data
            |> Enum.sort_by(fn char -> Map.get(char, "DamageDone", 0) end, :desc)
            |> Enum.take(20)

          # Extract labels (character names) and data (damage done and final blows)
          labels = Enum.map(sorted_data, fn char -> Map.get(char, "Name", "Unknown") end)
          damage_done = Enum.map(sorted_data, fn char -> Map.get(char, "DamageDone", 0) end)
          final_blows = Enum.map(sorted_data, fn char -> Map.get(char, "FinalBlows", 0) end)

          # Create a simpler chart configuration that matches QuickChart's expected format
          chart_config = %{
            "type" => "bar",
            "data" => %{
              "labels" => labels,
              "datasets" => [
                %{
                  "label" => "Damage Done",
                  "data" => damage_done,
                  "backgroundColor" => "rgba(255, 77, 77, 0.7)",
                  "borderColor" => "rgba(255, 77, 77, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y"
                },
                %{
                  "label" => "Final Blows",
                  "data" => final_blows,
                  "backgroundColor" => "rgba(54, 162, 235, 0.7)",
                  "borderColor" => "rgba(54, 162, 235, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y1"
                }
              ]
            },
            "options" => %{
              "responsive" => true,
              "title" => %{
                "display" => true,
                "text" => "Top Damage Done and Final Blows",
                "fontColor" => "white"
              },
              "scales" => %{
                "yAxes" => [
                  %{
                    "id" => "y",
                    "type" => "linear",
                    "position" => "left",
                    "ticks" => %{
                      "beginAtZero" => true,
                      "fontColor" => "white"
                    },
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Damage Done",
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "color" => "rgba(255, 255, 255, 0.1)"
                    }
                  },
                  %{
                    "id" => "y1",
                    "type" => "linear",
                    "position" => "right",
                    "ticks" => %{
                      "beginAtZero" => true,
                      "fontColor" => "white"
                    },
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Final Blows",
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "display" => false
                    }
                  }
                ],
                "xAxes" => [
                  %{
                    "ticks" => %{
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "color" => "rgba(255, 255, 255, 0.1)"
                    }
                  }
                ]
              },
              "legend" => %{
                "labels" => %{
                  "fontColor" => "white"
                }
              }
            },
            "backgroundColor" => @chart_background_color
          }

          # Generate chart URL
          generate_chart_url(chart_config)
        else
          Logger.warning("No character performance data available, generating fallback chart")
          generate_fallback_chart("Damage and Final Blows", "No character performance data available")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for combined losses.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_combined_losses_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract character losses data from TPS data
        character_losses_data = extract_character_losses_data(data)

        if is_list(character_losses_data) and length(character_losses_data) > 0 do
          # Sort by losses value (descending) and take top 10
          sorted_data =
            character_losses_data
            |> Enum.sort_by(fn char -> Map.get(char, "LossesValue", 0) end, :desc)
            |> Enum.take(10)

          # Extract labels (character names) and data (losses value and count)
          labels = Enum.map(sorted_data, fn char -> Map.get(char, "CharacterName", "Unknown") end)
          losses_value = Enum.map(sorted_data, fn char -> Map.get(char, "LossesValue", 0) end)
          losses_count = Enum.map(sorted_data, fn char -> Map.get(char, "LossesCount", 0) end)

          # Create chart configuration
          chart_config = %{
            "type" => "bar",
            "data" => %{
              "labels" => labels,
              "datasets" => [
                %{
                  "label" => "Losses Value",
                  "data" => losses_value,
                  "backgroundColor" => "rgba(255, 99, 132, 0.7)",
                  "borderColor" => "rgba(255, 99, 132, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y"
                },
                %{
                  "label" => "Losses Count",
                  "data" => losses_count,
                  "backgroundColor" => "rgba(54, 162, 235, 0.7)",
                  "borderColor" => "rgba(54, 162, 235, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y1"
                }
              ]
            },
            "options" => %{
              "responsive" => true,
              "title" => %{
                "display" => true,
                "text" => "Combined Losses",
                "fontColor" => "white"
              },
              "scales" => %{
                "yAxes" => [
                  %{
                    "id" => "y",
                    "type" => "linear",
                    "position" => "left",
                    "ticks" => %{
                      "beginAtZero" => true,
                      "fontColor" => "white"
                    },
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Losses Value",
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "color" => "rgba(255, 255, 255, 0.1)"
                    }
                  },
                  %{
                    "id" => "y1",
                    "type" => "linear",
                    "position" => "right",
                    "ticks" => %{
                      "beginAtZero" => true,
                      "fontColor" => "white"
                    },
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Losses Count",
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "display" => false
                    }
                  }
                ],
                "xAxes" => [
                  %{
                    "ticks" => %{
                      "fontColor" => "white",
                      "maxRotation" => 45,
                      "minRotation" => 45
                    },
                    "gridLines" => %{
                      "display" => false
                    }
                  }
                ]
              },
              "legend" => %{
                "labels" => %{
                  "fontColor" => "white"
                }
              }
            },
            "backgroundColor" => @chart_background_color
          }

          # Generate chart URL
          generate_chart_url(chart_config)
        else
          Logger.warning("No character losses data available, generating fallback chart")
          generate_fallback_chart("Combined Losses", "No character losses data available")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for kill activity.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kill_activity_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract kill activity data from TPS data
        kill_activity_data = extract_kill_activity_data(data)

        if is_list(kill_activity_data) and length(kill_activity_data) > 0 do
          # Sort by kill count (descending) and take top 10
          sorted_data =
            kill_activity_data
            |> Enum.sort_by(fn char -> Map.get(char, "KillCount", 0) end, :desc)
            |> Enum.take(10)

          # Extract labels (character names) and data (kill count and efficiency)
          labels = Enum.map(sorted_data, fn char -> Map.get(char, "CharacterName", "Unknown") end)
          kill_count = Enum.map(sorted_data, fn char -> Map.get(char, "KillCount", 0) end)

          efficiency =
            Enum.map(sorted_data, fn char ->
              kill_count = Map.get(char, "KillCount", 0)
              death_count = Map.get(char, "DeathCount", 0)
              total = kill_count + death_count

              if total > 0 do
                kill_count / total * 100
              else
                0
              end
            end)

          # Create chart configuration
          chart_config = %{
            "type" => "bar",
            "data" => %{
              "labels" => labels,
              "datasets" => [
                %{
                  "label" => "Kill Count",
                  "data" => kill_count,
                  "backgroundColor" => "rgba(75, 192, 192, 0.7)",
                  "borderColor" => "rgba(75, 192, 192, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y"
                },
                %{
                  "label" => "Efficiency (%)",
                  "data" => efficiency,
                  "backgroundColor" => "rgba(255, 159, 64, 0.7)",
                  "borderColor" => "rgba(255, 159, 64, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y1"
                }
              ]
            },
            "options" => %{
              "responsive" => true,
              "title" => %{
                "display" => true,
                "text" => "Kill Activity",
                "fontColor" => "white"
              },
              "scales" => %{
                "yAxes" => [
                  %{
                    "id" => "y",
                    "type" => "linear",
                    "position" => "left",
                    "ticks" => %{
                      "beginAtZero" => true,
                      "fontColor" => "white"
                    },
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Kill Count",
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "color" => "rgba(255, 255, 255, 0.1)"
                    }
                  },
                  %{
                    "id" => "y1",
                    "type" => "linear",
                    "position" => "right",
                    "ticks" => %{
                      "beginAtZero" => true,
                      "fontColor" => "white",
                      "max" => 100
                    },
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Efficiency (%)",
                      "fontColor" => "white"
                    },
                    "gridLines" => %{
                      "display" => false
                    }
                  }
                ],
                "xAxes" => [
                  %{
                    "ticks" => %{
                      "fontColor" => "white",
                      "maxRotation" => 45,
                      "minRotation" => 45
                    },
                    "gridLines" => %{
                      "display" => false
                    }
                  }
                ]
              },
              "legend" => %{
                "labels" => %{
                  "fontColor" => "white"
                }
              }
            },
            "backgroundColor" => @chart_background_color
          }

          # Generate chart URL
          generate_chart_url(chart_config)
        else
          Logger.warning("No kill activity data available, generating fallback chart")
          generate_fallback_chart("Kill Activity", "No kill activity data available")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions to extract data from TPS response

  defp extract_character_performance_data(data) do
    # Log the structure of the TPS data
    Logger.info("TPS data structure: #{inspect(Map.keys(data))}")

    # Based on the TPS data structure, we need to look for the character damage and final blows chart
    # in the TimeFrames array, under Charts

    # First, try to find the TimeFrames array
    time_frames = Map.get(data, "TimeFrames", [])

    # Log for debugging
    Logger.info("Found #{length(time_frames)} time frames in TPS data")

    if length(time_frames) > 0 do
      # Log the structure of the first time frame
      first_frame = List.first(time_frames)
      Logger.info("First time frame structure: #{inspect(Map.keys(first_frame))}")

      # Log the charts in the first time frame if available
      if Map.has_key?(first_frame, "Charts") do
        charts = Map.get(first_frame, "Charts", [])
        Logger.info("Found #{length(charts)} charts in first time frame")

        # Log the IDs of the charts
        chart_ids = Enum.map(charts, fn chart -> Map.get(chart, "ID", "unknown") end)
        Logger.info("Chart IDs: #{inspect(chart_ids)}")
      end
    end

    # Look through each time frame for the character damage and final blows chart
    character_data =
      Enum.reduce_while(time_frames, [], fn time_frame, _acc ->
        # Get the charts array from the time frame
        charts = Map.get(time_frame, "Charts", [])

        # Look for a chart with ID containing "characterDamageAndFinalBlowsChart" or similar
        damage_chart = Enum.find(charts, fn chart ->
          id = Map.get(chart, "ID", "")
          String.contains?(id, "characterDamageAndFinalBlowsChart") or
          String.contains?(id, "DamageFinalBlows") or
          String.contains?(id, "damage_final_blows")
        end)

        if damage_chart do
          # Found the chart, now parse the data
          Logger.info("Found damage chart with ID: #{Map.get(damage_chart, "ID", "unknown")}")
          data_str = Map.get(damage_chart, "Data", "[]")

          # Log a sample of the data string
          sample_length = min(String.length(data_str), 200)
          Logger.info("Data string sample (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

          # Try to parse the JSON data
          case Jason.decode(data_str) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              # Successfully parsed the data
              Logger.info("Successfully parsed character performance data with #{length(parsed_data)} entries")
              if length(parsed_data) > 0 do
                # Log the structure of the first entry
                first_entry = List.first(parsed_data)
                Logger.info("First entry structure: #{inspect(Map.keys(first_entry))}")
              end
              {:halt, parsed_data}
            {:ok, _} ->
              # Data is not a list
              Logger.warning("Character performance data is not a list")
              {:cont, []}
            {:error, reason} ->
              # Failed to parse the data
              Logger.error("Failed to parse character performance data: #{inspect(reason)}")
              {:cont, []}
          end
        else
          # Chart not found in this time frame, continue to the next one
          {:cont, []}
        end
      end)

    # If we didn't find any data, try a different approach
    if character_data == [] do
      Logger.warning("Could not find character performance data in TimeFrames, trying alternative approach")

      # Try to find any chart with damage and final blows data
      Enum.reduce_while(time_frames, [], fn time_frame, _acc ->
        charts = Map.get(time_frame, "Charts", [])

        # Try each chart
        Enum.reduce_while(charts, [], fn chart, _chart_acc ->
          chart_id = Map.get(chart, "ID", "unknown")
          Logger.info("Trying chart with ID: #{chart_id}")

          data_str = Map.get(chart, "Data", "[]")

          # Log a sample of the data string
          sample_length = min(String.length(data_str), 200)
          Logger.info("Data string sample (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

          case Jason.decode(data_str) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              # Check if the data has the expected structure
              has_expected_structure = Enum.any?(parsed_data, fn item ->
                is_map(item) and Map.has_key?(item, "DamageDone") and Map.has_key?(item, "FinalBlows")
              end)

              Logger.info("Chart #{chart_id} has expected structure: #{has_expected_structure}")

              if has_expected_structure do
                Logger.info("Found alternative character performance data with #{length(parsed_data)} entries")
                if length(parsed_data) > 0 do
                  # Log the structure of the first entry
                  first_entry = List.first(parsed_data)
                  Logger.info("First entry structure: #{inspect(Map.keys(first_entry))}")
                end
                {:halt, parsed_data}
              else
                {:cont, []}
              end
            {:ok, _} ->
              Logger.warning("Chart #{chart_id} data is not a list")
              {:cont, []}
            {:error, reason} ->
              Logger.error("Failed to parse chart #{chart_id} data: #{inspect(reason)}")
              {:cont, []}
          end
        end)
        |> case do
          [] -> {:cont, []}
          found_data -> {:halt, found_data}
        end
      end)
    else
      character_data
    end
  end

  defp extract_character_losses_data(data) do
    # Log the structure of the TPS data
    Logger.info("TPS data structure for losses: #{inspect(Map.keys(data))}")

    # Similar approach as extract_character_performance_data
    time_frames = Map.get(data, "TimeFrames", [])

    Logger.info("Looking for character losses data in #{length(time_frames)} time frames")

    if length(time_frames) > 0 do
      # Log the structure of the first time frame
      first_frame = List.first(time_frames)
      Logger.info("First time frame structure for losses: #{inspect(Map.keys(first_frame))}")

      # Log the charts in the first time frame if available
      if Map.has_key?(first_frame, "Charts") do
        charts = Map.get(first_frame, "Charts", [])
        Logger.info("Found #{length(charts)} charts in first time frame for losses")

        # Log the IDs of the charts
        chart_ids = Enum.map(charts, fn chart -> Map.get(chart, "ID", "unknown") end)
        Logger.info("Chart IDs for losses: #{inspect(chart_ids)}")
      end
    end

    character_data =
      Enum.reduce_while(time_frames, [], fn time_frame, _acc ->
        charts = Map.get(time_frame, "Charts", [])

        losses_chart = Enum.find(charts, fn chart ->
          id = Map.get(chart, "ID", "")
          String.contains?(id, "combinedLossesChart") or
          String.contains?(id, "CombinedLosses") or
          String.contains?(id, "combined_losses") or
          String.contains?(id, "CharacterLosses")
        end)

        if losses_chart do
          Logger.info("Found losses chart with ID: #{Map.get(losses_chart, "ID", "unknown")}")
          data_str = Map.get(losses_chart, "Data", "[]")

          # Log a sample of the data string
          sample_length = min(String.length(data_str), 200)
          Logger.info("Losses data string sample (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

          case Jason.decode(data_str) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              Logger.info("Successfully parsed character losses data with #{length(parsed_data)} entries")
              if length(parsed_data) > 0 do
                # Log the structure of the first entry
                first_entry = List.first(parsed_data)
                Logger.info("First losses entry structure: #{inspect(Map.keys(first_entry))}")
              end
              {:halt, parsed_data}
            {:ok, _} ->
              Logger.warning("Character losses data is not a list")
              {:cont, []}
            {:error, reason} ->
              Logger.error("Failed to parse character losses data: #{inspect(reason)}")
              {:cont, []}
          end
        else
          {:cont, []}
        end
      end)

    # If we didn't find any data, try a different approach
    if character_data == [] do
      Logger.warning("Could not find character losses data in TimeFrames, trying alternative approach")

      # Try to find any chart with losses data
      Enum.reduce_while(time_frames, [], fn time_frame, _acc ->
        charts = Map.get(time_frame, "Charts", [])

        Enum.reduce_while(charts, [], fn chart, _chart_acc ->
          chart_id = Map.get(chart, "ID", "unknown")
          Logger.info("Trying chart with ID for losses: #{chart_id}")

          data_str = Map.get(chart, "Data", "[]")

          # Log a sample of the data string
          sample_length = min(String.length(data_str), 200)
          Logger.info("Data string sample for losses (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

          case Jason.decode(data_str) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              # Check if the data has the expected structure
              has_expected_structure = Enum.any?(parsed_data, fn item ->
                is_map(item) and (Map.has_key?(item, "LossesValue") or Map.has_key?(item, "LossesCount"))
              end)

              Logger.info("Chart #{chart_id} has expected losses structure: #{has_expected_structure}")

              if has_expected_structure do
                Logger.info("Found alternative character losses data with #{length(parsed_data)} entries")
                if length(parsed_data) > 0 do
                  # Log the structure of the first entry
                  first_entry = List.first(parsed_data)
                  Logger.info("First alternative losses entry structure: #{inspect(Map.keys(first_entry))}")
                end
                {:halt, parsed_data}
              else
                {:cont, []}
              end
            {:ok, _} ->
              Logger.warning("Chart #{chart_id} losses data is not a list")
              {:cont, []}
            {:error, reason} ->
              Logger.error("Failed to parse chart #{chart_id} losses data: #{inspect(reason)}")
              {:cont, []}
          end
        end)
        |> case do
          [] -> {:cont, []}
          found_data -> {:halt, found_data}
        end
      end)
    else
      character_data
    end
  end

  defp extract_kill_activity_data(data) do
    # Log the structure of the TPS data
    Logger.info("TPS data structure for kill activity: #{inspect(Map.keys(data))}")

    # Similar approach as the other extraction functions
    time_frames = Map.get(data, "TimeFrames", [])

    Logger.info("Looking for kill activity data in #{length(time_frames)} time frames")

    if length(time_frames) > 0 do
      # Log the structure of the first time frame
      first_frame = List.first(time_frames)
      Logger.info("First time frame structure for kill activity: #{inspect(Map.keys(first_frame))}")

      # Log the charts in the first time frame if available
      if Map.has_key?(first_frame, "Charts") do
        charts = Map.get(first_frame, "Charts", [])
        Logger.info("Found #{length(charts)} charts in first time frame for kill activity")

        # Log the IDs of the charts
        chart_ids = Enum.map(charts, fn chart -> Map.get(chart, "ID", "unknown") end)
        Logger.info("Chart IDs for kill activity: #{inspect(chart_ids)}")
      end
    end

    activity_data =
      Enum.reduce_while(time_frames, [], fn time_frame, _acc ->
        charts = Map.get(time_frame, "Charts", [])

        activity_chart = Enum.find(charts, fn chart ->
          id = Map.get(chart, "ID", "")
          String.contains?(id, "killActivityOverTimeChart") or
          String.contains?(id, "KillActivity") or
          String.contains?(id, "kill_activity")
        end)

        if activity_chart do
          Logger.info("Found activity chart with ID: #{Map.get(activity_chart, "ID", "unknown")}")
          data_str = Map.get(activity_chart, "Data", "[]")

          # Log a sample of the data string
          sample_length = min(String.length(data_str), 200)
          Logger.info("Activity data string sample (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

          case Jason.decode(data_str) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              Logger.info("Successfully parsed kill activity data with #{length(parsed_data)} entries")
              if length(parsed_data) > 0 do
                # Log the structure of the first entry
                first_entry = List.first(parsed_data)
                Logger.info("First activity entry structure: #{inspect(Map.keys(first_entry))}")
              end
              {:halt, parsed_data}
            {:ok, _} ->
              Logger.warning("Kill activity data is not a list")
              {:cont, []}
            {:error, reason} ->
              Logger.error("Failed to parse kill activity data: #{inspect(reason)}")
              {:cont, []}
          end
        else
          {:cont, []}
        end
      end)

    # If we didn't find any data, try a different approach
    if activity_data == [] do
      Logger.warning("Could not find kill activity data in TimeFrames, trying alternative approach")

      # Try to find any chart with time-based kill data
      Enum.reduce_while(time_frames, [], fn time_frame, _acc ->
        charts = Map.get(time_frame, "Charts", [])

        Enum.reduce_while(charts, [], fn chart, _chart_acc ->
          chart_id = Map.get(chart, "ID", "unknown")
          Logger.info("Trying chart with ID for activity: #{chart_id}")

          data_str = Map.get(chart, "Data", "[]")

          # Log a sample of the data string
          sample_length = min(String.length(data_str), 200)
          Logger.info("Data string sample for activity (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

          case Jason.decode(data_str) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              # Check if the data has the expected structure
              has_expected_structure = Enum.any?(parsed_data, fn item ->
                is_map(item) and Map.has_key?(item, "Time") and Map.has_key?(item, "Kills")
              end)

              Logger.info("Chart #{chart_id} has expected activity structure: #{has_expected_structure}")

              if has_expected_structure do
                Logger.info("Found alternative kill activity data with #{length(parsed_data)} entries")
                if length(parsed_data) > 0 do
                  # Log the structure of the first entry
                  first_entry = List.first(parsed_data)
                  Logger.info("First alternative activity entry structure: #{inspect(Map.keys(first_entry))}")
                end
                {:halt, parsed_data}
              else
                {:cont, []}
              end
            {:ok, _} ->
              Logger.warning("Chart #{chart_id} activity data is not a list")
              {:cont, []}
            {:error, reason} ->
              Logger.error("Failed to parse chart #{chart_id} activity data: #{inspect(reason)}")
              {:cont, []}
          end
        end)
        |> case do
          [] -> {:cont, []}
          found_data -> {:halt, found_data}
        end
      end)
    else
      activity_data
    end
  end

  # Helper function to generate chart URL
  defp generate_chart_url(chart_config) do
    # Validate chart configuration
    if is_nil(chart_config) do
      Logger.error("Chart configuration is nil")
      {:error, "Chart configuration is nil"}
    else
      # Ensure required fields are present
      has_type = Map.has_key?(chart_config, "type")
      has_data = Map.has_key?(chart_config, "data")
      has_options = Map.has_key?(chart_config, "options")

      if not (is_map(chart_config) and has_type and has_data) do
        Logger.error("Invalid chart configuration: missing required fields. Config: #{inspect(chart_config)}")
        {:error, "Invalid chart configuration: missing required fields"}
      else
        # Ensure options is present and is a map
        chart_config = if not has_options do
          Logger.warning("Chart configuration missing options field, adding default options")
          # Add default options if missing
          Map.put(chart_config, "options", %{
            "responsive" => true,
            "plugins" => %{
              "title" => %{
                "display" => true,
                "text" => "Chart",
                "color" => @chart_text_color
              }
            }
          })
        else
          chart_config
        end

        # Log the chart configuration for debugging
        Logger.debug("Chart configuration: #{inspect(chart_config)}")

        # Convert chart configuration to JSON
        case Jason.encode(chart_config) do
          {:ok, json} ->
            # Log the JSON for debugging (truncated to avoid huge logs)
            json_sample = String.slice(json, 0, 500)
            Logger.debug("Chart JSON (truncated): #{json_sample}...")

            # URL encode the JSON
            encoded_config = URI.encode_www_form(json)

            # Construct the URL
            url = "#{@quickcharts_url}?c=#{encoded_config}&w=#{@chart_width}&h=#{@chart_height}"

            # Log the URL length for debugging
            Logger.info("Generated chart URL with length: #{String.length(url)}")

            {:ok, url}

          {:error, reason} ->
            Logger.error("Failed to encode chart configuration: #{inspect(reason)}")
            {:error, "Failed to encode chart configuration: #{inspect(reason)}"}
        end
      end
    end
  end

  # Helper function to generate a fallback chart when no data is available
  defp generate_fallback_chart(title, message) do
    # Create a simple bar chart with "No Data Available" message
    chart_config = %{
      "type" => "bar",
      "data" => %{
        "labels" => ["No Data Available"],
        "datasets" => [
          %{
            "label" => "No Data",
            "data" => [0],
            "backgroundColor" => "rgba(200, 200, 200, 0.5)",
            "borderColor" => "rgba(200, 200, 200, 1)",
            "borderWidth" => 1
          }
        ]
      },
      "options" => %{
        "responsive" => true,
        "title" => %{
          "display" => true,
          "text" => title,
          "fontColor" => "white"
        },
        "subtitle" => %{
          "display" => true,
          "text" => message,
          "fontColor" => "white"
        },
        "scales" => %{
          "yAxes" => [
            %{
              "ticks" => %{
                "beginAtZero" => true,
                "fontColor" => "white"
              },
              "gridLines" => %{
                "color" => "rgba(255, 255, 255, 0.1)"
              }
            }
          ],
          "xAxes" => [
            %{
              "ticks" => %{
                "fontColor" => "white"
              },
              "gridLines" => %{
                "display" => false
              }
            }
          ]
        },
        "legend" => %{
          "display" => false
        }
      },
      "backgroundColor" => @chart_background_color
    }

    # Log the fallback chart configuration
    Logger.debug("Fallback chart configuration: #{inspect(chart_config)}")

    # Generate chart URL
    generate_chart_url(chart_config)
  end

  @doc """
  Sends a chart to Discord as an embed.

  Args:
    - chart_type: The type of chart to generate (:damage_final_blows, :combined_losses, or :kill_activity)
    - title: The title for the Discord embed
    - description: The description for the Discord embed

  Returns :ok on success, {:error, reason} on failure.
  """
  def send_chart_to_discord(chart_type, title, description) do
    # Generate the chart URL based on the chart type
    chart_result = case chart_type do
      :damage_final_blows -> generate_damage_final_blows_chart()
      :combined_losses -> generate_combined_losses_chart()
      :kill_activity -> generate_kill_activity_chart()
      _ -> {:error, "Invalid chart type"}
    end

    case chart_result do
      {:ok, url} ->
        # Get the notifier
        notifier = WandererNotifier.NotifierFactory.get_notifier()

        # Log the URL for debugging
        Logger.info("Sending chart to Discord: #{url}")

        # Check if URL is too long for Discord embed (Discord has a limit around 2000 characters)
        url_length = String.length(url)

        if url_length > 1000 do
          # URL is too long, download the image and send as attachment instead
          Logger.info("URL is too long (#{url_length} chars), sending as attachment instead")
          send_chart_as_attachment(notifier, url, title, description)
        else
          # URL is acceptable length, send as embed
          notifier.send_embed(title, description, url)
        end

      {:error, reason} ->
        Logger.error("Failed to generate chart: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper function to download chart image and send as attachment
  defp send_chart_as_attachment(notifier, url, title, description) do
    # Create a temporary file for the image
    temp_file = Path.join(System.tmp_dir(), "chart_#{:rand.uniform(1000000)}.png")

    try do
      # Download the image
      case HTTPoison.get(url, [], [follow_redirect: true]) do
        {:ok, %{status_code: 200, body: body}} ->
          # Write the image to the temp file
          File.write!(temp_file, body)

          # Send the image as an attachment with the title and description
          Logger.info("Sending chart as attachment: #{temp_file}")
          notifier.send_file(temp_file, title, description)

        {:ok, %{status_code: status_code}} ->
          error_msg = "Failed to download chart image: HTTP status #{status_code}"
          Logger.error(error_msg)
          {:error, error_msg}

        {:error, reason} ->
          error_msg = "Failed to download chart image: #{inspect(reason)}"
          Logger.error(error_msg)
          {:error, error_msg}
      end
    rescue
      e ->
        Logger.error("Error sending chart as attachment: #{inspect(e)}")
        {:error, "Error sending chart as attachment: #{inspect(e)}"}
    after
      # Clean up the temp file
      File.rm(temp_file)
    end
  end

  @doc """
  Test function to generate and send all charts to Discord.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.JSChartAdapter.test_send_all_charts()
  ```
  """
  def test_send_all_charts do
    Logger.info("Testing JS chart generation and sending to Discord")

    # Send damage and final blows chart
    damage_final_blows_result = send_chart_to_discord(
      :damage_final_blows,
      "Damage and Final Blows Analysis",
      "Top characters by damage done and final blows"
    )

    # Send combined losses chart
    combined_losses_result = send_chart_to_discord(
      :combined_losses,
      "Combined Losses Analysis",
      "Top characters by losses value and count"
    )

    # Send kill activity chart
    kill_activity_result = send_chart_to_discord(
      :kill_activity,
      "Kill Activity Analysis",
      "Top characters by kill count and efficiency"
    )

    # Return results
    %{
      damage_final_blows: damage_final_blows_result,
      combined_losses: combined_losses_result,
      kill_activity: kill_activity_result
    }
  end

  @doc """
  Logs the TPS data structure for debugging purposes.
  Returns the TPS data if available, or an error message.
  """
  def debug_tps_data_structure do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Log the top-level keys
        Logger.info("TPS data top-level keys: #{inspect(Map.keys(data))}")

        # Check for TimeFrames
        time_frames = Map.get(data, "TimeFrames", [])
        Logger.info("Found #{length(time_frames)} time frames")

        if length(time_frames) > 0 do
          # Log the structure of the first time frame
          first_frame = List.first(time_frames)
          Logger.info("First time frame keys: #{inspect(Map.keys(first_frame))}")

          # Check for Charts
          if Map.has_key?(first_frame, "Charts") do
            charts = Map.get(first_frame, "Charts", [])
            Logger.info("Found #{length(charts)} charts in first time frame")

            # Log the IDs of all charts
            chart_ids = Enum.map(charts, fn chart -> Map.get(chart, "ID", "unknown") end)
            Logger.info("Chart IDs: #{inspect(chart_ids)}")

            # Log the structure of the first chart
            if length(charts) > 0 do
              first_chart = List.first(charts)
              Logger.info("First chart keys: #{inspect(Map.keys(first_chart))}")

              # Check for Data
              if Map.has_key?(first_chart, "Data") do
                data_str = Map.get(first_chart, "Data", "[]")
                sample_length = min(String.length(data_str), 200)
                Logger.info("Data string sample (first #{sample_length} chars): #{String.slice(data_str, 0, sample_length)}")

                # Try to parse the data
                case Jason.decode(data_str) do
                  {:ok, parsed_data} when is_list(parsed_data) ->
                    Logger.info("Successfully parsed data with #{length(parsed_data)} entries")
                    if length(parsed_data) > 0 do
                      first_entry = List.first(parsed_data)
                      Logger.info("First entry keys: #{inspect(Map.keys(first_entry))}")
                    end
                  {:ok, _} ->
                    Logger.warning("Data is not a list")
                  {:error, reason} ->
                    Logger.error("Failed to parse data: #{inspect(reason)}")
                end
              end
            end
          end
        end

        # Return the data
        {:ok, data}

      {:loading, message} ->
        Logger.info("TPS data is still loading: #{message}")
        {:loading, message}

      {:error, reason} ->
        Logger.error("Failed to get TPS data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generates a chart based on the provided type.

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_chart(chart_type) do
    case chart_type do
      :damage_final_blows -> generate_damage_final_blows_chart()
      :combined_losses -> generate_combined_losses_chart()
      :kill_activity -> generate_kill_activity_chart()
      _ -> {:error, "Invalid chart type"}
    end
  end
end
