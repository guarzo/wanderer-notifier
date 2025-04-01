defmodule WandererNotifier.Api.Character.Activity do
  @moduledoc """
  Module for handling character activity data fetching and processing.
  """

  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Fetches character activity data for the specified number of days.
  Returns {:ok, data} on success or {:error, reason} on failure.
  """
  def fetch_activity_data(days \\ 7) do
    AppLogger.api_info("Fetching character activity data", days: days)

    case CharactersClient.get_character_activity(nil, days) do
      {:ok, data} ->
        AppLogger.api_info("Retrieved character activity data")

        AppLogger.api_debug("Character activity data structure",
          data: inspect(data, pretty: true, limit: 2000)
        )

        {:ok, data}

      {:error, reason} = error ->
        AppLogger.api_error("Error fetching character activity data", error: inspect(reason))
        error
    end
  end

  @doc """
  Processes the raw activity data into a standardized format.
  """
  def process_activity_data(data) when is_map(data) do
    cond do
      # If data is a map with a "data" key that contains a list
      is_map(data) && Map.has_key?(data, "data") && is_list(data["data"]) ->
        AppLogger.api_debug("Found data structure",
          type: "map with 'data' key containing a list",
          record_count: length(data["data"])
        )

        {:ok, data["data"]}

      # If data is a map with a "data" key that contains a map with a "characters" key
      is_map(data) && Map.has_key?(data, "data") && is_map(data["data"]) &&
          Map.has_key?(data["data"], "characters") ->
        char_data = data["data"]["characters"]

        AppLogger.api_debug("Found data structure",
          type: "nested map with characters key",
          record_count: length(char_data)
        )

        {:ok, char_data}

      true ->
        AppLogger.api_warn("Unexpected data structure", data_preview: inspect(data, limit: 200))
        {:error, "Invalid data structure"}
    end
  end

  def process_activity_data(data) when is_list(data) do
    AppLogger.api_debug("Found data structure", type: "list", record_count: length(data))
    {:ok, data}
  end

  def process_activity_data(nil) do
    {:error, "No data provided"}
  end

  def process_activity_data(_) do
    {:error, "Invalid data type"}
  end
end
