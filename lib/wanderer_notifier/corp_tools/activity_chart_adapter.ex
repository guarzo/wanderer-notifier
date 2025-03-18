defmodule WandererNotifier.CorpTools.ActivityChartAdapter do
  @moduledoc """
  Adapter module for EVE Corp Tools chart generation and integration.
  """

  require Logger

  # We'll use the Notifier factory instead of direct DiscordNotifier calls
  alias WandererNotifier.NotifierFactory

  # Remove unused alias
  # alias WandererNotifier.CorpTools.ChartHelpers

  @doc """
  Generates a character activity chart based on activity data.
  Returns {:ok, url, title} on success, {:error, reason} on failure.
  """
  def generate_activity_summary_chart(activity_data) do
    Logger.info("Generating character activity summary chart")
    Logger.info("Activity data: #{inspect(activity_data, pretty: true, limit: 2000)}")

    if activity_data == nil do
      Logger.error("No activity data provided to generate_activity_summary_chart")
      {:error, "No activity data provided"}
    else
      try do
        # Log the type and structure
        type_info = cond do
          is_nil(activity_data) -> "nil"
          is_map(activity_data) -> "map"
          is_list(activity_data) -> "list"
          is_binary(activity_data) -> "binary"
          true -> "other: #{inspect(activity_data)}"
        end
        Logger.info("Activity data type: #{type_info}")

        # Extract character data based on format
        characters = cond do
          # If activity_data is already a list of character data
          is_list(activity_data) ->
            Logger.info("Found activity data list with #{length(activity_data)} character records")
            activity_data

          # If activity_data is a map with a "data" key that contains a list
          is_map(activity_data) && Map.has_key?(activity_data, "data") && is_list(activity_data["data"]) ->
            data = activity_data["data"]
            Logger.info("Found data in map['data'] key: #{length(data)} character records")
            data

          # If activity_data is a map with a "characters" key
          is_map(activity_data) && Map.has_key?(activity_data, "characters") ->
            data = activity_data["characters"]
            Logger.info("Found #{length(data)} character records in the data")
            data

          # Return empty list for other formats
          true ->
            Logger.error("Invalid data format - couldn't extract character data")
            Logger.error("Available keys: #{inspect(if is_map(activity_data), do: Map.keys(activity_data), else: "not a map")}")
            []
        end

        if characters && length(characters) > 0 do
          # Sort by the number of connections in descending order and take top 10
          top_characters = characters
            |> Enum.sort_by(fn char -> Map.get(char, "connections", 0) end, :desc)
            |> Enum.take(10)

          Logger.info("Sorted #{length(top_characters)} characters for activity chart")

          # Extract labels (character names) and values (connection counts)
          labels = Enum.map(top_characters, fn char ->
            character = Map.get(char, "character", %{})
            Map.get(character, "name", "Unknown")
          end)
          connection_data = Enum.map(top_characters, fn char -> Map.get(char, "connections", 0) end)

          # Create the chart configuration
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
              },
              plugins: %{
                backgroundColorPlugin: %{
                  color: "rgb(47, 49, 54)"
                }
              }
            }
          }

          Logger.info("Chart configuration created successfully")
          chart_json = Jason.encode!(chart)
          chart_url = "https://quickchart.io/chart?c=#{URI.encode(chart_json)}&backgroundColor=rgb(47,49,54)"
          title = "Character Activity Summary"

          Logger.info("Chart URL generated successfully")
          {:ok, chart_url, title}
        else
          Logger.error("No character data available for activity chart")
          create_no_data_chart("Activity Summary")
        end
      rescue
        e ->
          Logger.error("Error generating activity summary chart: #{inspect(e)}")
          {:error, "Error generating chart: #{inspect(e)}"}
      end
    end
  end

  @doc """
  Generates an activity timeline chart showing character activity over time.

  Returns {:ok, chart_url, title} on success, {:error, reason} on failure.
  """
  def generate_activity_timeline_chart(activity_data) do
    Logger.info("Generating activity timeline chart")

    if activity_data == nil do
      Logger.error("No activity data provided to generate_activity_timeline_chart")
      create_no_data_chart("Activity Timeline")
    else
      try do
        # Extract character data based on format
        characters = cond do
          # If activity_data is already a list of character data
          is_list(activity_data) ->
            Logger.info("Found activity data list with #{length(activity_data)} character records")
            activity_data

          # If activity_data is a map with a "data" key that contains a list
          is_map(activity_data) && Map.has_key?(activity_data, "data") && is_list(activity_data["data"]) ->
            data = activity_data["data"]
            Logger.info("Found data in map['data'] key: #{length(data)} character records")
            data

          # If activity_data is a map with a "characters" key
          is_map(activity_data) && Map.has_key?(activity_data, "characters") ->
            data = activity_data["characters"]
            Logger.info("Found #{length(data)} character records in the data")
            data

          # Return empty list for other formats
          true ->
            Logger.error("Invalid data format - couldn't extract character data")
            Logger.error("Available keys: #{inspect(if is_map(activity_data), do: Map.keys(activity_data), else: "not a map")}")
            []
        end

        if characters && length(characters) > 0 do
          # Group data by timestamp (hour)
          timestamp_data = characters
          |> Enum.map(fn char ->
            timestamp = Map.get(char, "timestamp", DateTime.utc_now() |> DateTime.to_string())
            {timestamp, Map.get(char, "connections", 0)}
          end)
          |> Enum.group_by(
            fn {timestamp, _} ->
              {:ok, dt, _} = DateTime.from_iso8601(timestamp)
              DateTime.to_date(dt)
            end,
            fn {_, connections} -> connections end
          )
          |> Enum.map(fn {date, connections} ->
            {Date.to_string(date), Enum.sum(connections)}
          end)
          |> Enum.sort_by(fn {date, _} -> date end)

          # Extract labels (dates) and values (connection counts)
          labels = Enum.map(timestamp_data, fn {date, _} -> date end)
          connection_data = Enum.map(timestamp_data, fn {_, connections} -> connections end)

          # Create the chart configuration
          chart = %{
            type: "line",
            data: %{
              labels: labels,
              datasets: [
                %{
                  label: "Total Connections",
                  backgroundColor: "rgba(75, 192, 192, 0.2)",
                  borderColor: "rgb(75, 192, 192)",
                  data: connection_data,
                  fill: true
                }
              ]
            },
            options: %{
              title: %{
                display: true,
                text: "Activity Timeline",
                fontColor: "white"
              },
              scales: %{
                xAxes: [%{
                  ticks: %{fontColor: "white"},
                  gridLines: %{color: "rgba(255, 255, 255, 0.1)"}
                }],
                yAxes: [%{
                  ticks: %{beginAtZero: true, fontColor: "white"},
                  gridLines: %{color: "rgba(255, 255, 255, 0.1)"}
                }]
              },
              legend: %{
                labels: %{fontColor: "white"}
              },
              plugins: %{
                backgroundColorPlugin: %{
                  color: "rgb(47, 49, 54)"
                }
              }
            }
          }

          Logger.info("Timeline chart configuration created successfully")
          chart_json = Jason.encode!(chart)
          chart_url = "https://quickchart.io/chart?c=#{URI.encode(chart_json)}&backgroundColor=rgb(47,49,54)"
          title = "Activity Timeline"

          {:ok, chart_url, title}
        else
          Logger.error("No character data available for timeline chart")
          create_no_data_chart("Activity Timeline")
        end
      rescue
        e ->
          Logger.error("Error generating activity timeline chart: #{inspect(e)}")
          {:error, "Error generating chart: #{inspect(e)}"}
      end
    end
  end

  @doc """
  Generates an activity distribution chart showing character activity by hour of day.

  Returns {:ok, chart_url, title} on success, {:error, reason} on failure.
  """
  def generate_activity_distribution_chart(activity_data) do
    Logger.info("Generating activity distribution chart")

    if activity_data == nil do
      Logger.error("No activity data provided to generate_activity_distribution_chart")
      create_no_data_chart("Activity Distribution")
    else
      try do
        # Extract character data based on format
        characters = cond do
          # If activity_data is already a list of character data
          is_list(activity_data) ->
            Logger.info("Found activity data list with #{length(activity_data)} character records")
            activity_data

          # If activity_data is a map with a "data" key that contains a list
          is_map(activity_data) && Map.has_key?(activity_data, "data") && is_list(activity_data["data"]) ->
            data = activity_data["data"]
            Logger.info("Found data in map['data'] key: #{length(data)} character records")
            data

          # If activity_data is a map with a "characters" key
          is_map(activity_data) && Map.has_key?(activity_data, "characters") ->
            data = activity_data["characters"]
            Logger.info("Found #{length(data)} character records in the data")
            data

          # Return empty list for other formats
          true ->
            Logger.error("Invalid data format - couldn't extract character data")
            Logger.error("Available keys: #{inspect(if is_map(activity_data), do: Map.keys(activity_data), else: "not a map")}")
            []
        end

        if characters && length(characters) > 0 do
          # Group data by hour of day
          hour_data = characters
          |> Enum.map(fn char ->
            timestamp = Map.get(char, "timestamp", DateTime.utc_now() |> DateTime.to_string())
            {timestamp, Map.get(char, "connections", 0)}
          end)
          |> Enum.group_by(
            fn {timestamp, _} ->
              {:ok, dt, _} = DateTime.from_iso8601(timestamp)
              DateTime.to_time(dt).hour
            end,
            fn {_, connections} -> connections end
          )
          |> Enum.map(fn {hour, connections} ->
            {hour, Enum.sum(connections)}
          end)
          |> Enum.sort_by(fn {hour, _} -> hour end)

          # Fill in missing hours with zero values
          all_hours = 0..23 |> Enum.to_list()
          hour_data_map = Enum.into(hour_data, %{})

          complete_hour_data = Enum.map(all_hours, fn hour ->
            {hour, Map.get(hour_data_map, hour, 0)}
          end)

          # Extract labels (hours) and values (connection counts)
          labels = Enum.map(complete_hour_data, fn {hour, _} -> "#{hour}:00" end)
          connection_data = Enum.map(complete_hour_data, fn {_, connections} -> connections end)

          # Create the chart configuration
          chart = %{
            type: "bar",
            data: %{
              labels: labels,
              datasets: [
                %{
                  label: "Connections by Hour",
                  backgroundColor: "rgba(153, 102, 255, 0.5)",
                  borderColor: "rgb(153, 102, 255)",
                  borderWidth: 1,
                  data: connection_data
                }
              ]
            },
            options: %{
              title: %{
                display: true,
                text: "Activity Distribution by Hour",
                fontColor: "white"
              },
              scales: %{
                xAxes: [%{
                  ticks: %{fontColor: "white"},
                  gridLines: %{color: "rgba(255, 255, 255, 0.1)"}
                }],
                yAxes: [%{
                  ticks: %{beginAtZero: true, fontColor: "white"},
                  gridLines: %{color: "rgba(255, 255, 255, 0.1)"}
                }]
              },
              legend: %{
                labels: %{fontColor: "white"}
              },
              plugins: %{
                backgroundColorPlugin: %{
                  color: "rgb(47, 49, 54)"
                }
              }
            }
          }

          Logger.info("Distribution chart configuration created successfully")
          chart_json = Jason.encode!(chart)
          chart_url = "https://quickchart.io/chart?c=#{URI.encode(chart_json)}&backgroundColor=rgb(47,49,54)"
          title = "Activity Distribution by Hour"

          {:ok, chart_url, title}
        else
          Logger.error("No character data available for distribution chart")
          create_no_data_chart("Activity Distribution")
        end
      rescue
        e ->
          Logger.error("Error generating activity distribution chart: #{inspect(e)}")
          {:error, "Error generating chart: #{inspect(e)}"}
      end
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
  def send_chart_to_discord(activity_data, chart_title \\ nil) do
    # Log the activity data type
    type_info = cond do
      is_nil(activity_data) -> "nil"
      is_map(activity_data) -> "map with keys: #{inspect(Map.keys(activity_data))}"
      is_list(activity_data) -> "list with #{length(activity_data)} items"
      is_binary(activity_data) -> "binary: #{String.slice(activity_data, 0, 50)}"
      true -> "other: #{inspect(activity_data, limit: 50)}"
    end
    Logger.info("Activity data type: #{type_info}")

    # Generate chart
    case generate_activity_summary_chart(activity_data) do
      {:ok, chart_url, title} ->
        Logger.info("Sending chart to Discord: #{title}")
        # Use the notifier directly rather than webhook URLs
        # Get the notifier instance
        notifier = NotifierFactory.get_notifier()
        # Create a simple description
        description = "Character activity summary chart"
        # Use a consistent color
        color = 3_447_003  # Discord blue color

        # Send the chart as an embed with the image URL
        title = chart_title || title
        result = notifier.send_image_embed(title, description, chart_url, color)

        case result do
          :ok ->
            Logger.info("Successfully sent chart to Discord: #{title}")
            {:ok, chart_url, title}
          {:error, reason} ->
            Logger.error("Failed to send chart to Discord: #{inspect(reason)}")
            {:error, "Failed to send chart to Discord: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to generate chart: #{inspect(reason)}")
        {:error, "Failed to generate chart: #{inspect(reason)}"}
    end
  end

  @doc """
  Sends all activity charts to Discord.
  Returns a list of {chart_type, result} tuples.
  """
  def send_all_charts_to_discord(activity_data) do
    # Log the activity data type
    type_info = cond do
      is_nil(activity_data) -> "nil"
      is_map(activity_data) -> "map with keys: #{inspect(Map.keys(activity_data))}"
      is_list(activity_data) -> "list with #{length(activity_data)} items"
      is_binary(activity_data) -> "binary: #{String.slice(activity_data, 0, 50)}"
      true -> "other: #{inspect(activity_data, limit: 50)}"
    end
    Logger.info("Activity data for all charts - type: #{type_info}")

    # Define chart types to send
    chart_types = [
      "Activity Summary",
      "Activity Timeline",
      "Activity Distribution"
    ]

    # Send each chart and collect results
    results = Enum.map(chart_types, fn chart_type ->
      Logger.info("Sending #{chart_type} chart to Discord")

      result = case chart_type do
        "Activity Summary" -> send_chart_to_discord(activity_data, chart_type)
        "Activity Timeline" -> send_activity_timeline_chart(activity_data)
        "Activity Distribution" -> send_activity_distribution_chart(activity_data)
        _ -> {:error, "Unknown chart type: #{chart_type}"}
      end

      {chart_type, result}
    end)

    # Log results summary
    success_count = Enum.count(results, fn {_, result} -> match?({:ok, _, _}, result) end)
    Logger.info("Completed sending all charts to Discord. Success: #{success_count}/#{length(results)}")

    results
  end

  @doc """
  Test function for development only
  """
  def test_send_all_charts do
    Logger.info("Testing sending all charts")
    # Pass nil to use mock data
    send_all_charts_to_discord(nil)
  end

  @doc """
  Test function to check if quickchart.io is accessible and the HTTP client works.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.ActivityChartAdapter.test_quickchart_access()
  ```
  """
  def test_quickchart_access do
    Logger.info("Testing quickchart.io access")

    # Create a very simple chart URL
    test_url = "https://quickchart.io/chart?c=%7B%22type%22%3A%22bar%22%2C%22data%22%3A%7B%22labels%22%3A%5B%22Test%22%5D%2C%22datasets%22%3A%5B%7B%22label%22%3A%22Test%22%2C%22data%22%3A%5B1%5D%7D%5D%7D%7D"

    # Try to download the image
    Logger.info("Trying to download image from #{test_url}")

    download_result = case WandererNotifier.Http.Client.get(test_url) do
      {:ok, %{status_code: 200, body: body}} ->
        size = byte_size(body)
        Logger.info("Successfully downloaded image (#{size} bytes)")
        {:ok, "Image downloaded successfully (#{size} bytes)"}

      {:ok, %{status_code: status}} ->
        Logger.error("Failed to download chart image: HTTP status #{status}")
        {:error, "HTTP status #{status}"}

      {:error, reason} ->
        Logger.error("Failed to download chart image: #{inspect(reason)}")
        {:error, inspect(reason)}
    end

    # Return the result
    download_result
  end

  # Private helpers

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

  # Create a "No Data Available" chart
  #
  # Returns {:ok, url, title} with a generic chart URL.
  defp create_no_data_chart(chart_type) do
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
        }
      }
    }

    # Encode the config and create the URL
    try do
      json = Jason.encode!(chart_config)
      url = "https://quickchart.io/chart?c=#{URI.encode(json)}&backgroundColor=rgb(47,49,54)"
      Logger.info("Successfully created 'No Data Available' chart URL")
      {:ok, url, title}
    rescue
      e ->
        Logger.error("Error creating 'No Data Available' chart: #{inspect(e)}")
        # Super simple fallback URL that should always work
        fallback_url = "https://quickchart.io/chart?c=%7B%22type%22%3A%22bar%22%2C%22data%22%3A%7B%22labels%22%3A%5B%22No%20Data%22%5D%2C%22datasets%22%3A%5B%7B%22label%22%3A%22No%20Data%20Available%22%2C%22data%22%3A%5B0%5D%7D%5D%7D%7D&backgroundColor=rgb(47,49,54)"
        {:ok, fallback_url, title}
    end
  end

  # Function is currently unused but may be needed later
  # defp generate_dataset_label_pair(labels, values, color, label) do
  #   %{
  #     labels: labels,
  #     datasets: [
  #       %{
  #         label: label,
  #         data: values,
  #         backgroundColor: color
  #       }
  #     ]
  #   }
  # end

  @doc """
  Sends a chart to Discord with title and description for the embed.

  Args:
    - chart_type: The type of chart to generate (:activity_summary, :activity_timeline, or :activity_distribution)
    - title: The title for the Discord embed
    - description: The description for the Discord embed

  Returns :ok on success, {:error, reason} on failure.
  """
  def send_chart_to_discord(chart_type, _title, _description) do
    # Just call the 2-argument version since we don't currently use the title and description
    send_chart_to_discord(chart_type)
  end

  def send_activity_timeline_chart(activity_data) do
    Logger.info("Generating activity timeline chart")

    case generate_activity_timeline_chart(activity_data) do
      {:ok, chart_url, title} ->
        Logger.info("Sending timeline chart to Discord: #{title}")

        # Use the notifier directly
        notifier = NotifierFactory.get_notifier()
        description = "Character activity timeline chart"
        color = 3_447_003  # Discord blue color

        # Use send_image_embed to embed the image in Discord
        result = notifier.send_image_embed(title, description, chart_url, color)

        case result do
          :ok ->
            Logger.info("Successfully sent timeline chart to Discord")
            {:ok, chart_url, title}
          {:error, reason} ->
            Logger.error("Failed to send timeline chart to Discord: #{inspect(reason)}")
            {:error, "Failed to send timeline chart to Discord: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to generate timeline chart: #{inspect(reason)}")
        {:error, "Failed to generate timeline chart: #{inspect(reason)}"}
    end
  end

  def send_activity_distribution_chart(activity_data) do
    Logger.info("Generating activity distribution chart")

    case generate_activity_distribution_chart(activity_data) do
      {:ok, chart_url, title} ->
        Logger.info("Sending distribution chart to Discord: #{title}")

        # Use the notifier directly
        notifier = NotifierFactory.get_notifier()
        description = "Character activity distribution chart"
        color = 3_447_003  # Discord blue color

        # Use send_image_embed to embed the image in Discord
        result = notifier.send_image_embed(title, description, chart_url, color)

        case result do
          :ok ->
            Logger.info("Successfully sent distribution chart to Discord")
            {:ok, chart_url, title}
          {:error, reason} ->
            Logger.error("Failed to send distribution chart to Discord: #{inspect(reason)}")
            {:error, "Failed to send distribution chart to Discord: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to generate distribution chart: #{inspect(reason)}")
        {:error, "Failed to generate distribution chart: #{inspect(reason)}"}
    end
  end
end
