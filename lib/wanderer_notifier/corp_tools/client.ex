defmodule WandererNotifier.CorpTools.Client do
  @moduledoc """
  Client for interacting with the EVE Corp Tools Service API.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Config

  @doc """
  Test function to fetch and log TPS data.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.Client.test_tps_data()
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
  Returns :ok if the API is operational, {:error, reason} otherwise.
  """
  def health_check do
    url = "#{Config.corp_tools_api_url()}/health"
    headers = [
      {"Authorization", "Bearer #{Config.corp_tools_api_token()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Performing health check for EVE Corp Tools API at #{url}")

    case HttpClient.request("GET", url, headers, "", max_retries: 1) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, %{"status" => "ok"}} ->
            Logger.info("EVE Corp Tools API health check successful")
            :ok
          {:ok, response} ->
            Logger.error("EVE Corp Tools API health check failed: #{inspect(response)}")
            {:error, "Invalid health check response"}
          {:error, error} ->
            Logger.error("Failed to parse EVE Corp Tools API health check response: #{inspect(error)}")
            {:error, "Failed to parse response"}
        end
      {:ok, %{status_code: status, body: body}} ->
        Logger.error("EVE Corp Tools API health check failed with status #{status}: #{body}")
        {:error, "API returned status #{status}"}
      {:error, %HTTPoison.Error{reason: :econnrefused}} ->
        Logger.warning("EVE Corp Tools API connection refused. The service might be running on a different host or port.")
        Logger.info("If the service is running on your host machine, use 'host.docker.internal' instead of 'localhost' in CORP_TOOLS_API_URL")
        {:error, :connection_refused}
      {:error, reason} ->
        Logger.error("EVE Corp Tools API health check request failed: #{inspect(reason)}")
        {:error, reason}
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
  WandererNotifier.CorpTools.Client.test_tracked_entities()
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

        Logger.info("Entity counts: #{length(alliances)} alliances, #{length(corporations)} corporations, #{length(characters)} characters")

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
end
