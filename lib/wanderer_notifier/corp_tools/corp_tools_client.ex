defmodule WandererNotifier.CorpTools.CorpToolsClient do
  @moduledoc """
  Client for the EVE Corp Tools API.

  This module handles all communication with the EVE Corp Tools API,
  which provides EVE Online Tranquility Player Stats (TPS) data and
  other corporation-related functionality.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Config

  @doc """
  Test function to fetch and log TPS data.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.CorpToolsClient.test_tps_data()
  ```
  """
  def test_tps_data do
    Logger.info("Testing TPS data API call")

    case get_tps_data() do
      {:ok, data} ->
        Logger.info("TPS data retrieved successfully")
        Logger.info("Data structure: #{inspect(data, pretty: true, limit: 10000)}")
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
  Performs a health check on the EVE Corp Tools API.
  Returns :ok if the API is operational or if corp tools is disabled, {:error, reason} otherwise.
  """
  def health_check do
    # Skip the health check if corp tools is disabled
    if !Config.corp_tools_enabled?() do
      :ok
    else
      url = "#{Config.corp_tools_api_url()}/health"
      # Don't send Authorization header for health check
      headers = [
        {"Content-Type", "application/json"}
      ]

      case HttpClient.request("GET", url, headers, "", max_retries: 1, follow_redirects: true) do
        {:ok, %{status_code: status, body: body}} when status in 200..299 ->
          case Jason.decode(body) do
            {:ok, %{"status" => "ok"}} ->
              :ok

            {:ok, response} ->
              Logger.error("EVE Corp Tools API health check failed: #{inspect(response)}")
              {:error, "Invalid health check response"}

            {:error, error} ->
              Logger.error(
                "Failed to parse EVE Corp Tools API health check response: #{inspect(error)}"
              )

              {:error, "Failed to parse response"}
          end

        # Log redirects but don't treat them as errors
        {:ok, %HTTPoison.MaybeRedirect{status_code: status, redirect_url: redirect_url}}
        when status in [301, 302, 307, 308] ->
          Logger.warning("EVE Corp Tools API health check redirected to #{redirect_url}")

          # Follow the redirect manually and check the health at the new URL
          # Don't send Authorization header for health check redirect
          redirect_headers = [
            {"Content-Type", "application/json"}
          ]

          case HttpClient.request("GET", redirect_url, redirect_headers, "", max_retries: 1) do
            {:ok, %{status_code: redirect_status, body: redirect_body}}
            when redirect_status in 200..299 ->
              case Jason.decode(redirect_body) do
                {:ok, %{"status" => "ok"}} ->
                  :ok

                {:ok, redirect_response} ->
                  Logger.error(
                    "EVE Corp Tools API health check failed after redirect: #{inspect(redirect_response)}"
                  )

                  {:error, "Invalid health check response after redirect"}

                {:error, redirect_error} ->
                  Logger.error(
                    "Failed to parse EVE Corp Tools API health check response after redirect: #{inspect(redirect_error)}"
                  )

                  {:error, "Failed to parse response after redirect"}
              end

            {:ok, %{status_code: redirect_status, body: redirect_body}} ->
              Logger.error(
                "EVE Corp Tools API health check failed after redirect with status #{redirect_status}: #{redirect_body}"
              )

              {:error, "API returned status #{redirect_status} after redirect"}

            {:error, redirect_reason} ->
              Logger.error(
                "EVE Corp Tools API health check request failed after redirect: #{inspect(redirect_reason)}"
              )

              {:error, redirect_reason}
          end

        {:ok, %{status_code: status, body: body}} ->
          Logger.error("EVE Corp Tools API health check failed with status #{status}: #{body}")
          {:error, "API returned status #{status}"}

        {:error, %HTTPoison.Error{reason: :econnrefused}} ->
          Logger.warning(
            "EVE Corp Tools API connection refused. The service might be running on a different host or port."
          )

          Logger.info(
            "If the service is running on your host machine, use 'host.docker.internal' instead of 'localhost' in CORP_TOOLS_API_URL"
          )

          {:error, :connection_refused}

        {:error, reason} ->
          Logger.error("EVE Corp Tools API health check request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Retrieves tracked entities from the EVE Corp Tools API.
  Returns {:ok, data} on success, {:error, reason} on failure.
  """
  def get_tracked_entities do
    url = "#{Config.corp_tools_api_url()}/tracked"

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Fetching tracked entities from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.info("Successfully retrieved tracked entities: #{inspect(Map.keys(data))}")
            {:ok, data}

          {:error, error} ->
            Logger.error("Failed to parse tracked entities response: #{inspect(error)}")
            {:error, "Failed to parse response"}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to get tracked entities with status #{status}: #{body}")
        {:error, "API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning("EVE Corp Tools API connection refused when fetching tracked entities")
        {:error, :connection_refused}

      {:error, reason} ->
        Logger.error("Tracked entities request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Retrieves Time, Pilots, Ships (TPS) data from the EVE Corp Tools API.
  Returns {:ok, data} on success, {:error, reason} on failure.

  The API may return a 206 status code if the data is still loading,
  in which case this function returns {:loading, message}.
  """
  def get_tps_data do
    url = "#{Config.corp_tools_api_url()}/tps-data"

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Fetching TPS data from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        Logger.info("TPS data response received with status 200")
        Logger.debug("TPS data response body: #{body}")

        case Jason.decode(body) do
          {:ok, data} ->
            Logger.info("Successfully retrieved TPS data with keys: #{inspect(Map.keys(data))}")
            {:ok, data}

          {:error, error} ->
            Logger.error("Failed to parse TPS data response: #{inspect(error)}")
            Logger.error("Raw response body: #{body}")
            {:error, "Failed to parse response"}
        end

      {:ok, %{status_code: 206, body: body}} ->
        # 206 Partial Content means data is still loading
        Logger.info("TPS data is still loading: #{body}")
        {:loading, body}

      {:ok, %HTTPoison.MaybeRedirect{redirect_url: redirect_url}} ->
        # Handle redirects manually
        Logger.info("TPS data request redirected to #{redirect_url}, following...")

        # Make sure we use the same headers including authorization for the redirect
        case HttpClient.request("GET", redirect_url, headers) do
          {:ok, %{status_code: 200, body: body}} ->
            Logger.info("TPS data response received with status 200 after redirect")

            case Jason.decode(body) do
              {:ok, data} ->
                Logger.info("Successfully retrieved TPS data after redirect")
                {:ok, data}

              {:error, error} ->
                Logger.error(
                  "Failed to parse TPS data response after redirect: #{inspect(error)}"
                )

                {:error, "Failed to parse response"}
            end

          {:ok, %{status_code: 206, body: body}} ->
            # 206 Partial Content means data is still loading
            Logger.info("TPS data is still loading after redirect: #{body}")
            {:loading, body}

          {:ok, %{status_code: status, body: body}} ->
            Logger.error("Failed to get TPS data after redirect with status #{status}: #{body}")
            {:error, "API returned status #{status} after redirect"}

          {:error, redirect_reason} ->
            Logger.error("TPS data request failed after redirect: #{inspect(redirect_reason)}")
            {:error, redirect_reason}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to get TPS data with status #{status}")
        Logger.error("Error response body: #{body}")
        {:error, "API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning("EVE Corp Tools API connection refused when fetching TPS data")
        {:error, :connection_refused}

      {:error, reason} ->
        Logger.error("TPS data request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Triggers a refresh of TPS data on the EVE Corp Tools API.
  Returns :ok on success, {:error, reason} on failure.
  """
  def refresh_tps_data do
    url = "#{Config.corp_tools_api_url()}/refresh-tps"

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Triggering TPS data refresh on EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: status, body: _body}} when status in 200..299 ->
        Logger.info("Successfully triggered TPS data refresh")
        :ok

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to trigger TPS data refresh with status #{status}: #{body}")
        {:error, "API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning("EVE Corp Tools API connection refused when triggering TPS data refresh")
        {:error, :connection_refused}

      {:error, reason} ->
        Logger.error("TPS data refresh request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Appraises EVE Online loot items using the EVE Corp Tools API.

  Args:
    - items: A string containing a list of items and quantities, one per line.
      Example: "Tritanium 100\nPyerite 50\nMexallon 25"

  Returns:
    - {:ok, data} on success, where data is a map containing the appraisal results
    - {:error, reason} on failure
  """
  def appraise_loot(items) when is_binary(items) do
    url = "#{Config.corp_tools_api_url()}/appraise-loot"

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "text/plain"}
    ]

    Logger.info("Appraising loot using EVE Corp Tools API")

    case HttpClient.request("POST", url, headers, items) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.info("Successfully appraised loot")
            {:ok, data}

          {:error, error} ->
            Logger.error("Failed to parse loot appraisal response: #{inspect(error)}")
            {:error, "Failed to parse response"}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to appraise loot with status #{status}: #{body}")
        {:error, "API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning("EVE Corp Tools API connection refused when appraising loot")
        {:error, :connection_refused}

      {:error, reason} ->
        Logger.error("Loot appraisal request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Test function to fetch and log tracked entities.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.CorpToolsClient.test_tracked_entities()
  ```
  """
  def test_tracked_entities do
    Logger.info("Testing tracked entities API call")

    case get_tracked_entities() do
      {:ok, data} ->
        Logger.info("Tracked entities retrieved successfully")

        # Log counts of each entity type
        alliances = Map.get(data, "alliances", [])
        corporations = Map.get(data, "corporations", [])
        characters = Map.get(data, "characters", [])

        Logger.info(
          "Entity counts: #{length(alliances)} alliances, #{length(corporations)} corporations, #{length(characters)} characters"
        )

        # Log a sample of each type if available
        if length(alliances) > 0 do
          Logger.info("Sample alliance: #{inspect(Enum.at(alliances, 0), pretty: true)}")
        end

        if length(corporations) > 0 do
          Logger.info("Sample corporation: #{inspect(Enum.at(corporations, 0), pretty: true)}")
        end

        if length(characters) > 0 do
          Logger.info("Sample character: #{inspect(Enum.at(characters, 0), pretty: true)}")
        end

        {:ok, data}

      {:error, reason} ->
        Logger.error("Failed to get tracked entities: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Retrieves character activity data from the EVE Corp Tools API.
  Returns {:ok, data} on success, {:error, reason} on failure.
  """
  def get_activity_data do
    url = "#{Config.corp_tools_api_url()}/activity"

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Fetching character activity data from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.info("Successfully retrieved character activity data")
            {:ok, data}

          {:error, error} ->
            Logger.error("Failed to parse character activity data response: #{inspect(error)}")
            {:error, "Failed to parse response"}
        end

      {:ok, %HTTPoison.MaybeRedirect{redirect_url: redirect_url}} ->
        # Handle redirects manually
        Logger.info("Received redirect to #{redirect_url}, following...")

        case HttpClient.request("GET", redirect_url, headers) do
          {:ok, %{status_code: status, body: body}} when status in 200..299 ->
            case Jason.decode(body) do
              {:ok, data} ->
                Logger.info("Successfully retrieved character activity data after redirect")
                {:ok, data}

              {:error, error} ->
                Logger.error(
                  "Failed to parse character activity data response after redirect: #{inspect(error)}"
                )

                {:error, "Failed to parse response"}
            end

          {:ok, %{status_code: status, body: body}} ->
            Logger.error(
              "Failed to fetch character activity data after redirect: HTTP #{status}, #{body}"
            )

            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            Logger.error(
              "Error fetching character activity data after redirect: #{inspect(reason)}"
            )

            {:error, "Failed to fetch data after redirect: #{inspect(reason)}"}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to get character activity data with status #{status}: #{body}")
        {:error, "API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning(
          "EVE Corp Tools API connection refused when fetching character activity data"
        )

        {:error, :connection_refused}

      {:error, reason} ->
        Logger.error("Character activity data request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Retrieves recent Time, Pilots, Ships (TPS) data from the EVE Corp Tools API.
  This endpoint is specifically designed for chart generation.

  Returns {:ok, data} on success, {:error, reason} on failure.
  """
  def get_recent_tps_data do
    url = "#{Config.corp_tools_api_url()}/recent-tps-data"

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Fetching recent TPS data from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        Logger.info("Recent TPS data response received with status 200")
        Logger.info("Raw response body length: #{String.length(body)} bytes")

        # Check if body is empty or just whitespace
        if body == nil || String.trim(body) == "" do
          Logger.warning("Recent TPS data response body is empty")
          {:error, "API returned empty response body"}
        else
          case Jason.decode(body) do
            {:ok, data} ->
              # More detailed logging of the response structure
              Logger.info(
                "Successfully retrieved recent TPS data with keys: #{inspect(Map.keys(data))}"
              )

              # Log the exact structure of the response for debugging
              Logger.info(
                "Complete TPS data structure: #{inspect(data, pretty: true, limit: 50000)}"
              )

              # Check for specific structures we're interested in
              if Map.has_key?(data, "TimeFrames") do
                time_frames = Map.get(data, "TimeFrames")

                Logger.info(
                  "TimeFrames is a #{typeof(time_frames)} with #{length(time_frames)} items"
                )

                # Log structure of the first TimeFrame
                if is_list(time_frames) && length(time_frames) > 0 do
                  first_frame = List.first(time_frames)
                  Logger.info("First TimeFrame keys: #{inspect(Map.keys(first_frame))}")

                  # Look for the ship types data in the first frame
                  cond do
                    Map.has_key?(first_frame, "KillsByShipType") ->
                      Logger.info(
                        "KillsByShipType found in TimeFrame with #{map_size(first_frame["KillsByShipType"])} entries"
                      )

                    Map.has_key?(first_frame, "ShipTypes") ->
                      Logger.info(
                        "ShipTypes found in TimeFrame with #{map_size(first_frame["ShipTypes"])} entries"
                      )

                    true ->
                      Logger.info("No ship type data found in TimeFrame")
                  end
                end
              end

              # Log useful debug info about other expected keys
              ["KillsByShipType", "KillsByMonth", "TotalValue"]
              |> Enum.each(fn key ->
                if Map.has_key?(data, key) do
                  value = Map.get(data, key)
                  Logger.info("Found #{key}: #{inspect(value, limit: 300)}")
                else
                  Logger.info("Key #{key} not found in top-level data")
                end
              end)

              {:ok, data}

            {:error, error} ->
              Logger.error("Failed to parse recent TPS data response: #{inspect(error)}")
              Logger.error("Raw response body: #{body}")
              {:error, "Failed to parse response"}
          end
        end

      {:ok, %{status_code: 206, body: body}} ->
        # 206 Partial Content means data is still loading
        Logger.info("Recent TPS data is still loading: #{body}")
        {:loading, body}

      {:ok, %HTTPoison.MaybeRedirect{redirect_url: redirect_url}} ->
        # Handle redirects manually
        Logger.info("Recent TPS data request redirected to #{redirect_url}, following...")

        # Make sure we use the same headers including authorization for the redirect
        case HttpClient.request("GET", redirect_url, headers) do
          {:ok, %{status_code: 200, body: body}} ->
            Logger.info("Recent TPS data response received with status 200 after redirect")

            case Jason.decode(body) do
              {:ok, data} ->
                Logger.info("Successfully retrieved recent TPS data after redirect")
                {:ok, data}

              {:error, error} ->
                Logger.error(
                  "Failed to parse recent TPS data response after redirect: #{inspect(error)}"
                )

                {:error, "Failed to parse response"}
            end

          {:ok, %{status_code: 206, body: body}} ->
            # 206 Partial Content means data is still loading
            Logger.info("Recent TPS data is still loading after redirect: #{body}")
            {:loading, body}

          {:ok, %{status_code: status, body: body}} ->
            Logger.error(
              "Failed to get recent TPS data after redirect with status #{status}: #{body}"
            )

            {:error, "API returned status #{status} after redirect"}

          {:error, redirect_reason} ->
            Logger.error(
              "Recent TPS data request failed after redirect: #{inspect(redirect_reason)}"
            )

            {:error, redirect_reason}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to get recent TPS data with status #{status}")
        Logger.error("Error response body: #{body}")
        {:error, "API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning("EVE Corp Tools API connection refused when fetching recent TPS data")
        {:error, :connection_refused}

      {:error, reason} ->
        Logger.error("Recent TPS data request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Test function to fetch and log recent TPS data.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.CorpToolsClient.test_recent_tps_data()
  ```
  """
  def test_recent_tps_data do
    Logger.info("Testing recent TPS data API call")

    case get_recent_tps_data() do
      {:ok, data} ->
        Logger.info("Recent TPS data retrieved successfully")
        Logger.info("Data structure: #{inspect(data, pretty: true, limit: 10000)}")

        # Log specific sections if they exist
        if Map.has_key?(data, "KillsByShipType") do
          Logger.info(
            "KillsByShipType section found with #{map_size(data["KillsByShipType"])} entries"
          )
        end

        if Map.has_key?(data, "KillsByMonth") do
          Logger.info("KillsByMonth section found with #{map_size(data["KillsByMonth"])} entries")
        end

        if Map.has_key?(data, "TotalValue") do
          Logger.info("TotalValue found: #{data["TotalValue"]}")
        end

        {:ok, data}

      {:loading, message} ->
        Logger.info("Recent TPS data is still loading: #{message}")
        {:loading, message}

      {:error, reason} ->
        Logger.error("Failed to get recent TPS data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Add a helper function to log the type of a value
  defp typeof(term) when is_nil(term), do: "nil"
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_number(term), do: "number"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(_term), do: "unknown"
end
