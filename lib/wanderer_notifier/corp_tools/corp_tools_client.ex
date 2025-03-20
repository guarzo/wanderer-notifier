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
  
  # Private helper to build consistent API URLs
  defp build_api_url(endpoint) do
    base_url = Config.corp_tools_api_url()
    url = if String.ends_with?(base_url, "/service-api") do
      "#{base_url}/#{endpoint}"
    else
      "#{base_url}/service-api/#{endpoint}"
    end
    
    # Log the constructed URL (temporary for debugging)
    Logger.info("Corp Tools API URL: #{url}")
    
    url
  end

  @doc """
  Test function to fetch TPS data.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.CorpToolsClient.test_tps_data()
  ```
  """
  def test_tps_data do
    case get_tps_data() do
      {:ok, _data} = result ->
        Logger.debug("TPS data retrieved successfully")
        result

      {:loading, _message} = result ->
        Logger.debug("TPS data is still loading")
        result

      {:error, _reason} = result ->
        Logger.debug("Failed to get TPS data")
        result
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
      url = build_api_url("health")
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
    url = build_api_url("tracked")

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug("Fetching tracked entities from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.debug("Successfully retrieved tracked entities")
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
    url = build_api_url("recent-tps-data")

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug("Fetching TPS data from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        Logger.debug("TPS data response received with status 200")

        case Jason.decode(body) do
          {:ok, data} ->
            Logger.debug("Successfully retrieved TPS data")
            {:ok, data}

          {:error, error} ->
            Logger.error("Failed to parse TPS data response: #{inspect(error)}")
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
    url = build_api_url("refresh-tps")

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug("Triggering TPS data refresh on EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: status, body: _body}} when status in 200..299 ->
        Logger.debug("Successfully triggered TPS data refresh")
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
    url = build_api_url("appraise-loot")

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
  Test function to fetch tracked entities.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.CorpToolsClient.test_tracked_entities()
  ```
  """
  def test_tracked_entities do
    case get_tracked_entities() do
      {:ok, data} = result ->
        # Just log counts of each entity type without detailed inspection
        alliances = Map.get(data, "alliances", [])
        corporations = Map.get(data, "corporations", [])
        characters = Map.get(data, "characters", [])

        Logger.debug(
          "Entities count: #{length(alliances)} alliances, #{length(corporations)} corporations, #{length(characters)} characters"
        )

        result

      {:error, _reason} = result ->
        Logger.debug("Failed to get tracked entities")
        result
    end
  end

  @doc """
  Retrieves character activity data from the EVE Corp Tools API.
  Returns {:ok, data} on success, {:error, reason} on failure.
  """
  def get_activity_data do
    # Use the helper to build the URL consistently
    url = build_api_url("activity")

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug("Fetching character activity data from EVE Corp Tools API")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, data} ->
            Logger.debug("Successfully retrieved character activity data")
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
    # Use the helper to build the URL consistently
    url = build_api_url("recent-tps-data")

    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Fetching recent TPS data from EVE Corp Tools API: #{url}")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        Logger.debug("Recent TPS data response received with status 200")

        # Check if body is empty or just whitespace
        if body == nil || String.trim(body) == "" do
          Logger.warning("Recent TPS data response body is empty")
          {:error, "API returned empty response body"}
        else
          case Jason.decode(body) do
            {:ok, data} ->
              # Just log success without excessive data dumping
              Logger.debug("Successfully retrieved recent TPS data")
              {:ok, data}

            {:error, error} ->
              Logger.error("Failed to parse recent TPS data response: #{inspect(error)}")
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
  Test function to fetch recent TPS data.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.CorpToolsClient.test_recent_tps_data()
  ```
  """
  def test_recent_tps_data do
    case get_recent_tps_data() do
      {:ok, _data} = result ->
        Logger.debug("Recent TPS data retrieved successfully")
        result

      {:loading, _message} = result ->
        Logger.debug("Recent TPS data is still loading")
        result

      {:error, _reason} = result ->
        Logger.debug("Failed to get recent TPS data")
        result
    end
  end

  # Helper function to get a human-readable type (commented out as it's currently unused)
  # defp typeof(term) when is_nil(term), do: "nil"
  # defp typeof(term) when is_binary(term), do: "string"
  # defp typeof(term) when is_boolean(term), do: "boolean"
  # defp typeof(term) when is_number(term), do: "number"
  # defp typeof(term) when is_atom(term), do: "atom"
  # defp typeof(term) when is_list(term), do: "list"
  # defp typeof(term) when is_map(term), do: "map"
  # defp typeof(term) when is_tuple(term), do: "tuple"
  # defp typeof(term) when is_function(term), do: "function"
  # defp typeof(_term), do: "unknown"
end
