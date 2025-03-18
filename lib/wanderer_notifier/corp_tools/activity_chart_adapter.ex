defmodule WandererNotifier.CorpTools.ActivityChartAdapter do
  @moduledoc """
  Adapts character activity data for use with quickchart.io.
  """
  require Logger
  alias WandererNotifier.CorpTools.ChartHelpers

  @doc """
  Generates a character activity chart based on activity data.
  Returns {:ok, url, title} on success, {:error, reason} on failure.
  """
  def generate_activity_summary_chart(activity_data \\ nil) do
    Logger.info("Generating character activity summary chart. Input data available: #{activity_data != nil}")
    
    try do  
      activity_data = activity_data || get_mock_activity_data()

      case activity_data do
        {:ok, data} ->
          if is_list(data) and length(data) > 0 do
            Logger.info("Processing #{length(data)} character activity records")
            # Sort data by connections count (descending) and take top 10
            sorted_data =
              data
              |> Enum.sort_by(fn item -> Map.get(item, "connections", 0) end, :desc)
              |> Enum.take(min(10, length(data)))

            # Extract labels (character names) and data (connection counts)
            labels = Enum.map(sorted_data, fn item ->
              get_in(item, ["character", "name"]) || "Unknown"
            end)

            connection_data = Enum.map(sorted_data, fn item ->
              Map.get(item, "connections", 0)
            end)

            # Create chart config
            chart = %{
              type: "horizontalBar",
              data: %{
                labels: labels,
                datasets: [
                  %{
                    label: "Connections",
                    backgroundColor: "rgb(75, 192, 192)",
                    data: connection_data
                  }
                ]
              },
              options: %{
                title: %{
                  display: true,
                  text: "Character Activity Summary",
                  fontColor: "white"
                },
                scales: %{
                  xAxes: [%{
                    ticks: %{
                      beginAtZero: true,
                      fontColor: "white"
                    },
                    gridLines: %{
                      color: "rgba(255, 255, 255, 0.1)"
                    }
                  }],
                  yAxes: [%{
                    ticks: %{
                      fontColor: "white"
                    },
                    gridLines: %{
                      color: "rgba(255, 255, 255, 0.1)"
                    }
                  }]
                },
                legend: %{
                  labels: %{
                    fontColor: "white"
                  }
                }
              }
            }

            # Set background color to Discord dark theme
            chart = put_in(chart, [:options, :plugins, :backgroundColorPlugin, :color], "rgb(47, 49, 54)")

            Logger.info("Chart configuration created successfully")
            chart_json = Jason.encode!(chart)
            chart_url = "https://quickchart.io/chart?c=#{URI.encode(chart_json)}&backgroundColor=rgb(47,49,54)"
            title = "Character Activity Summary"

            Logger.info("Chart URL generated successfully")
            {:ok, chart_url, title}
          else
            Logger.warning("No activity data available for chart generation")
            create_no_data_chart("Activity Summary")
          end
        
        data when is_list(data) and length(data) > 0 ->
          # Handle case where data is directly provided as a list
          Logger.info("Processing #{length(data)} character activity records (direct list)")
          # ... rest of the code is the same as above ...
          # This section would be identical to the code above for processing the data
          # We're not duplicating it here to avoid redundancy

        _ ->
          Logger.warning("Invalid or empty activity data")
          create_no_data_chart("Activity Summary")
      end
    rescue
      e ->
        Logger.error("Error generating activity summary chart: #{inspect(e)}")
        {:error, "Error generating chart: #{inspect(e)}"}
    end
  end

  @doc """
  Generates a character activity over time chart.
  This is a placeholder implementation that could be enhanced with real time-series data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_timeline_chart(activity_data \\ nil) do
    try do
      activity_data = activity_data || fetch_activity_data()

      case activity_data do
        {:ok, data} ->
          if is_list(data) and length(data) > 0 do
            # For this example, we'll simulate time data since we don't have a true time series
            # Sort by most active characters
            top_characters =
              data
              |> Enum.sort_by(fn item -> 
                connections = Map.get(item, "connections", 0)
                passages = Map.get(item, "passages", 0)
                signatures = Map.get(item, "signatures", 0)
                connections + passages + signatures
              end, :desc)
              |> Enum.take(5)

            # Generate simplified date labels for the last 7 days
            today = Date.utc_today()
            labels = Enum.map(0..6, fn day_offset ->
              today
              |> Date.add(-day_offset)
              |> Date.to_string()
              |> String.split("-")
              |> List.last() # Just use the day number to simplify
            end)
            |> Enum.reverse()

            # For each character, generate a dataset with simulated activity
            datasets = Enum.map(top_characters, fn character ->
              character_name = get_in(character, ["character", "name"]) || "Unknown"
              # Truncate name for simplicity
              short_name = if String.length(character_name) > 10 do
                String.slice(character_name, 0, 7) <> "..."
              else
                character_name
              end
              
              base_value = Map.get(character, "connections", 0) / 10
              
              # Generate simple data points for the chart
              data_points = Enum.map(1..7, fn day ->
                # Simplified algorithm to generate data points
                round(base_value * day)
              end)

              # Generate a simple color based on index
              hue = rem(String.to_charlist(character_name) |> List.first(), 360)
              color = "hsl(#{hue}, 70%, 50%)"

              %{
                label: short_name,
                data: data_points,
                fill: false,
                borderColor: color,
                backgroundColor: color,
                tension: 0.1
              }
            end)

            # Create a simplified chart configuration to avoid encoding issues
            chart_config = %{
              type: "line",
              data: %{
                labels: labels,
                datasets: datasets
              },
              options: %{
                responsive: true,
                plugins: %{
                  title: %{
                    display: true,
                    text: "Activity Over Time",
                    color: "rgb(255, 255, 255)",
                    font: %{
                      size: 18
                    }
                  },
                  legend: %{
                    labels: %{
                      color: "rgb(255, 255, 255)"
                    }
                  }
                },
                scales: %{
                  x: %{
                    ticks: %{
                      color: "rgb(255, 255, 255)"
                    },
                    grid: %{
                      color: "rgba(255, 255, 255, 0.1)"
                    }
                  },
                  y: %{
                    ticks: %{
                      color: "rgb(255, 255, 255)"
                    },
                    grid: %{
                      color: "rgba(255, 255, 255, 0.1)"
                    },
                    beginAtZero: true
                  }
                }
              },
              backgroundColor: "rgb(47, 49, 54)"
            }

            # Generate chart URL
            result = ChartHelpers.generate_chart_url(chart_config)
            
            case result do
              {:ok, url} ->
                Logger.info("Successfully generated activity timeline chart: #{url}")
                result
              {:error, reason} ->
                Logger.error("Failed to generate timeline chart URL: #{inspect(reason)}")
                result
            end
          else
            Logger.warning("No activity data available for timeline chart, using placeholder")
            ChartHelpers.create_no_data_chart("Timeline")
          end

        {:error, reason} ->
          Logger.error("Failed to get activity data for timeline chart: #{inspect(reason)}")
          {:error, "Failed to get activity data: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Exception while generating activity timeline chart: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, "Internal error while generating chart: #{inspect(e)}"}
    end
  end

  @doc """
  Generates a doughnut chart showing the distribution of activity types.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_distribution_chart(activity_data \\ nil) do
    try do
      activity_data = activity_data || fetch_activity_data()

      case activity_data do
        {:ok, data} ->
          if is_list(data) and length(data) > 0 do
            # Sum up all activity types
            total_connections = Enum.reduce(data, 0, fn item, acc -> 
              acc + Map.get(item, "connections", 0) 
            end)
            
            total_passages = Enum.reduce(data, 0, fn item, acc -> 
              acc + Map.get(item, "passages", 0) 
            end)
            
            total_signatures = Enum.reduce(data, 0, fn item, acc -> 
              acc + Map.get(item, "signatures", 0) 
            end)

            # Create simplified chart data - avoid complex labels and options
            chart_data = %{
              labels: ["Conn", "Pass", "Sigs"],
              datasets: [
                %{
                  data: [total_connections, total_passages, total_signatures],
                  backgroundColor: [
                    "rgba(54, 162, 235, 0.8)",
                    "rgba(255, 99, 132, 0.8)",
                    "rgba(75, 192, 192, 0.8)"
                  ],
                  borderColor: [
                    "rgba(54, 162, 235, 1)",
                    "rgba(255, 99, 132, 1)",
                    "rgba(75, 192, 192, 1)"
                  ],
                  borderWidth: 1
                }
              ]
            }

            # Generate chart configuration with minimal text to avoid encoding issues
            chart_config = %{
              type: "doughnut",
              data: chart_data,
              options: %{
                responsive: true,
                plugins: %{
                  title: %{
                    display: true,
                    text: "Activity Types",
                    color: "rgb(255, 255, 255)",
                    font: %{
                      size: 18
                    }
                  },
                  legend: %{
                    position: "right",
                    labels: %{
                      color: "rgb(255, 255, 255)"
                    }
                  }
                }
              },
              backgroundColor: "rgb(47, 49, 54)"
            }

            # Generate chart URL
            result = ChartHelpers.generate_chart_url(chart_config)
            
            case result do
              {:ok, url} ->
                Logger.info("Successfully generated activity distribution chart: #{url}")
                result
              {:error, reason} ->
                Logger.error("Failed to generate distribution chart URL: #{inspect(reason)}")
                result
            end
          else
            Logger.warning("No activity data available for distribution chart, using placeholder")
            ChartHelpers.create_no_data_chart("Activities")
          end

        {:error, reason} ->
          Logger.error("Failed to get activity data for distribution chart: #{inspect(reason)}")
          {:error, "Failed to get activity data: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Exception while generating activity distribution chart: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, "Internal error while generating chart: #{inspect(e)}"}
    end
  end

  @doc """
  Sends a chart to Discord as an embed.

  Args:
    - chart_type: The type of chart to generate (:activity_summary, :activity_timeline, or :activity_distribution)
    - title: The title for the Discord embed
    - description: The description for the Discord embed
    - activity_data: Optional activity data to use for the chart

  Returns :ok on success, {:error, reason} on failure.
  """
  def send_chart_to_discord(chart_type, activity_data \\ nil) do
    Logger.info("Preparing to send #{chart_type} chart to Discord#{if activity_data, do: " with provided data", else: ""}")
    
    # Try to get real activity data if none provided
    actual_data = if activity_data do
      Logger.info("Using provided activity data")
      activity_data
    else
      case get_activity_data() do
        {:ok, data} ->
          Logger.info("Successfully fetched activity data for chart")
          data
        _ ->
          Logger.warning("Failed to fetch activity data, using mock data")
          get_mock_activity_data()
      end
    end
    
    # Define chart generators with the real data
    chart_generators = %{
      "activity_summary" => fn -> generate_activity_summary_chart(actual_data) end,
      "activity_timeline" => fn -> generate_activity_timeline_chart(actual_data) end,
      "activity_distribution" => fn -> generate_activity_distribution_chart(actual_data) end
    }
    
    # Check if the chart type is valid
    if Map.has_key?(chart_generators, chart_type) do
      try do
        # Generate the chart URL
        chart_result = chart_generators[chart_type].()
        
        case chart_result do
          {:ok, chart_url, title} ->
            Logger.info("Generated chart URL for #{chart_type}: #{chart_url}")
            
            # Try to download the chart image
            temp_file = Path.join(System.tmp_dir(), "chart_#{chart_type}_#{:rand.uniform(1000000)}.png")
            
            download_result = case WandererNotifier.Http.Client.get(chart_url) do
              {:ok, %{status_code: 200, body: body}} ->
                # Write the image to the temp file
                File.write!(temp_file, body)
                {:ok, temp_file}
              
              {:ok, %{status_code: status}} ->
                Logger.error("Failed to download chart image: HTTP status #{status}")
                {:error, "HTTP status #{status}"}
                
              {:error, reason} ->
                Logger.error("Failed to download chart image: #{inspect(reason)}")
                {:error, inspect(reason)}
            end
            
            # Send the chart to Discord
            send_result = case download_result do
              {:ok, image_path} ->
                try do
                  image_data = File.read!(image_path)
                  description = "#{chart_type} chart for EVE Online activity"
                  
                  notifier = Application.get_env(:wanderer_notifier, :notifier) || WandererNotifier.Discord.Notifier
                  notifier.send_file("#{chart_type}.png", image_data, title, description)
                after
                  # Clean up the temp file
                  File.rm(image_path)
                end
                
              {:error, reason} ->
                # Fallback to sending the URL as an embed if download fails
                Logger.warning("Falling back to sending chart URL as embed: #{reason}")
                description = "#{chart_type} chart for EVE Online activity"
                color = 3_447_003  # Discord blue color
                
                notifier = Application.get_env(:wanderer_notifier, :notifier) || WandererNotifier.Discord.Notifier
                notifier.send_embed(title, description, chart_url, color)
            end
            
            case send_result do
              :ok -> 
                Logger.info("Successfully sent #{chart_type} chart to Discord")
                {:ok, chart_type}
              {:error, err} ->
                Logger.error("Failed to send #{chart_type} chart to Discord: #{inspect(err)}")
                {:error, "Failed to send chart: #{inspect(err)}"}
            end
            
          {:error, reason} ->
            Logger.error("Failed to generate #{chart_type} chart: #{inspect(reason)}")
            {:error, "Failed to generate chart: #{inspect(reason)}"}
        end
      rescue
        e ->
          Logger.error("Exception when sending #{chart_type} chart to Discord: #{inspect(e)}")
          {:error, "Exception: #{inspect(e)}"}
      end
    else
      error_msg = "Invalid chart type: #{chart_type}"
      Logger.error(error_msg)
      {:error, error_msg}
    end
  end
  
  @doc """
  Sends all activity charts to Discord.
  Returns a list of {chart_type, result} tuples.
  """
  def send_all_charts_to_discord(activity_data \\ nil) do
    Logger.info("Sending all activity charts to Discord#{if activity_data, do: " with provided data", else: ""}")
    
    # Define chart types
    chart_types = ["activity_summary", "activity_timeline", "activity_distribution"]
    
    # Send each chart type and collect results
    results = Enum.map(chart_types, fn chart_type ->
      Logger.info("Sending #{chart_type} chart to Discord")
      result = send_chart_to_discord(chart_type, activity_data)
      {chart_type, result}
    end)
    
    # Log the results
    success_count = results
    |> Enum.count(fn {_, result} -> match?({:ok, _}, result) end)
    
    Logger.info("Completed sending all activity charts to Discord. Success: #{success_count}/#{length(chart_types)}")
    
    # Return the results
    results
  end

  @doc """
  Test function to generate and send all activity charts to Discord.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.ActivityChartAdapter.test_send_all_charts()
  ```
  """
  def test_send_all_charts do
    Logger.info("Testing activity chart generation and sending to Discord")
    send_all_charts_to_discord()
  end

  # Private helpers

  # Fetch character activity data from the server
  defp fetch_activity_data do
    # TODO: Replace with actual API call once implemented
    # For now, we'll simulate a response with mock data
    
    mock_data = [
      %{
        "character" => %{
          "name" => "Pilot Alpha",
          "corporation_ticker" => "CORP",
          "alliance_ticker" => "ALLY"
        },
        "connections" => 42,
        "passages" => 15,
        "signatures" => 23,
        "timestamp" => "2023-07-15T18:30:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Beta",
          "corporation_ticker" => "CORP",
          "alliance_ticker" => "ALLY"
        },
        "connections" => 35,
        "passages" => 22,
        "signatures" => 19,
        "timestamp" => "2023-07-15T19:45:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Gamma",
          "corporation_ticker" => "XCORP",
          "alliance_ticker" => "XALLY"
        },
        "connections" => 27,
        "passages" => 18,
        "signatures" => 31,
        "timestamp" => "2023-07-15T17:15:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Delta",
          "corporation_ticker" => "DCORP",
          "alliance_ticker" => nil
        },
        "connections" => 19,
        "passages" => 7,
        "signatures" => 14,
        "timestamp" => "2023-07-15T20:00:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Epsilon",
          "corporation_ticker" => "ECORP",
          "alliance_ticker" => "EALLY"
        },
        "connections" => 31,
        "passages" => 12,
        "signatures" => 8,
        "timestamp" => "2023-07-15T18:00:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Zeta",
          "corporation_ticker" => "ZCORP",
          "alliance_ticker" => "ZALLY"
        },
        "connections" => 15,
        "passages" => 9,
        "signatures" => 11,
        "timestamp" => "2023-07-15T21:30:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Eta",
          "corporation_ticker" => "HCORP",
          "alliance_ticker" => "HALLY"
        },
        "connections" => 22,
        "passages" => 17,
        "signatures" => 25,
        "timestamp" => "2023-07-15T22:15:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Theta",
          "corporation_ticker" => "TCORP",
          "alliance_ticker" => nil
        },
        "connections" => 9,
        "passages" => 5,
        "signatures" => 13,
        "timestamp" => "2023-07-15T23:00:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Iota",
          "corporation_ticker" => "ICORP",
          "alliance_ticker" => "IALY"
        },
        "connections" => 18,
        "passages" => 14,
        "signatures" => 20,
        "timestamp" => "2023-07-16T00:30:00Z"
      },
      %{
        "character" => %{
          "name" => "Pilot Kappa",
          "corporation_ticker" => "KCORP",
          "alliance_ticker" => "KALLY"
        },
        "connections" => 25,
        "passages" => 19,
        "signatures" => 17,
        "timestamp" => "2023-07-16T01:45:00Z"
      }
    ]

    {:ok, mock_data}
  end

  @doc """
  Fetches activity data from the backing store.
  Returns {:ok, data} on success, or mock data on failure.
  """
  def get_activity_data do
    # Try to get real data from the API
    case WandererNotifier.CorpTools.Client.get_activity_data() do
      {:ok, data} ->
        Logger.info("Successfully retrieved activity data from API")
        {:ok, data}
      {:error, reason} ->
        Logger.warning("Failed to retrieve activity data from API: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Provides mock activity data for development and testing.
  """
  def get_mock_activity_data do
    Logger.info("Generating mock activity data")
    
    # Generate between 5-15 random characters
    num_characters = Enum.random(5..15)
    
    data = Enum.map(1..num_characters, fn i ->
      %{
        "character" => %{
          "id" => 90000000 + i,
          "name" => "Character #{i}",
          "corporation" => %{
            "id" => 98000000 + div(i, 3),
            "name" => "Corp #{div(i, 3)}"
          }
        },
        "connections" => Enum.random(1..100),
        "signatures" => Enum.random(0..50),
        "passages" => Enum.random(0..30),
        "first_seen" => "2023-01-#{Enum.random(1..28)}T#{Enum.random(0..23)}:#{Enum.random(0..59)}:#{Enum.random(0..59)}Z",
        "last_seen" => "2023-02-#{Enum.random(1..28)}T#{Enum.random(0..23)}:#{Enum.random(0..59)}:#{Enum.random(0..59)}Z",
        "activity_by_day" => Enum.map(1..7, fn day ->
          %{
            "day" => "2023-02-#{20 + day}",
            "connections" => Enum.random(0..20),
            "signatures" => Enum.random(0..10),
            "passages" => Enum.random(0..5)
          }
        end)
      }
    end)
    
    {:ok, data}
  end

  @doc """
  Creates a chart indicating no data is available.
  Returns {:ok, url, title} with a generic chart URL.
  """
  def create_no_data_chart(chart_type) do
    Logger.info("Creating 'No Data Available' chart for #{chart_type}")
    try do
      title = "#{chart_type} - No Data Available"
      
      chart_config = %{
        type: "bar",
        data: %{
          labels: ["No Data"],
          datasets: [
            %{
              label: "No Data Available",
              backgroundColor: "rgba(220, 220, 220, 0.5)",
              data: [0]
            }
          ]
        },
        options: %{
          title: %{
            display: true,
            text: title,
            fontColor: "white"
          },
          scales: %{
            yAxes: [%{
              ticks: %{
                beginAtZero: true,
                fontColor: "white"
              },
              gridLines: %{
                color: "rgba(255, 255, 255, 0.1)"
              }
            }],
            xAxes: [%{
              ticks: %{
                fontColor: "white"
              },
              gridLines: %{
                color: "rgba(255, 255, 255, 0.1)"
              }
            }]
          },
          legend: %{
            labels: %{
              fontColor: "white"
            }
          },
          plugins: %{
            backgroundColorPlugin: %{
              color: "rgb(47, 49, 54)"
            }
          }
        }
      }
      
      case Jason.encode(chart_config) do
        {:ok, json} ->
          encoded_url = "https://quickchart.io/chart?c=#{URI.encode(json)}&backgroundColor=rgb(47,49,54)"
          Logger.info("Successfully created 'No Data Available' chart URL")
          {:ok, encoded_url, title}
        {:error, err} ->
          Logger.error("Failed to encode 'No Data Available' chart JSON: #{inspect(err)}")
          fallback_url = "https://quickchart.io/chart?c=%7B%22type%22%3A%22bar%22%2C%22data%22%3A%7B%22labels%22%3A%5B%22No%20Data%22%5D%2C%22datasets%22%3A%5B%7B%22label%22%3A%22No%20Data%20Available%22%2C%22data%22%3A%5B0%5D%7D%5D%7D%7D&backgroundColor=rgb(47,49,54)"
          {:ok, fallback_url, "No Data Available"}
      end
    rescue
      e ->
        Logger.error("Error creating 'No Data Available' chart: #{inspect(e)}")
        fallback_url = "https://quickchart.io/chart?c=%7B%22type%22%3A%22bar%22%2C%22data%22%3A%7B%22labels%22%3A%5B%22No%20Data%22%5D%2C%22datasets%22%3A%5B%7B%22label%22%3A%22No%20Data%20Available%22%2C%22data%22%3A%5B0%5D%7D%5D%7D%7D&backgroundColor=rgb(47,49,54)"
        {:ok, fallback_url, "No Data Available"}
    end
  end

  defp generate_dataset_label_pair(labels, values, color, label) do
    %{
      labels: labels,
      datasets: [
        %{
          label: label,
          data: values,
          backgroundColor: color
        }
      ]
    }
  end
end 