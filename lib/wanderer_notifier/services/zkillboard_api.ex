defmodule WandererNotifier.Services.ZKillboardApi do
  @moduledoc """
  Service for interacting with the zKillboard API.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @base_url "https://zkillboard.com/api"

  @doc """
  Gets kills for a specific character.
  Since startTime/endTime are no longer supported by the API, this gets all recent kills.
  Date filtering should be done in memory after fetching the kills.

  ## Parameters
    - character_id: The character ID to get kills for

  ## Returns
    {:ok, kills} | {:error, reason}
  """
  def get_character_kills(character_id) do
    url = "#{@base_url}/characterID/#{character_id}/"

    case HTTPoison.get(url, get_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        # Direct console log of the raw body
        Logger.info("ZKillboard raw response: #{body}")

        case Jason.decode(body) do
          {:ok, kills} when is_list(kills) ->
            {:ok, kills}

          {:ok, %{"error" => error}} ->
            AppLogger.api_error("zKillboard API returned error", %{error: error})
            {:error, error}

          error ->
            handle_json_error(error)
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        AppLogger.api_error("zKillboard API error", %{status_code: code})
        {:error, "HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        AppLogger.api_error("zKillboard API request failed", %{error: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Gets details for a specific killmail.

  ## Parameters
    - kill_id: The killmail ID to fetch

  ## Returns
    {:ok, kill_data} | {:error, reason}
  """
  def get_killmail(kill_id) do
    url = "#{@base_url}/killID/#{kill_id}/"

    case HTTPoison.get(url, get_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, [kill_data | _]} -> {:ok, kill_data}
          {:ok, []} -> {:error, :not_found}
          error -> handle_json_error(error)
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        AppLogger.api_error("zKillboard API error", status_code: code)
        {:error, "HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        AppLogger.api_error("zKillboard API request failed", error: inspect(reason))
        {:error, reason}
    end
  end

  # Private functions

  defp get_headers do
    user_agent = "WandererNotifier/1.0 (https://github.com/guarzo/wanderer-notifier)"

    [
      {"User-Agent", user_agent},
      {"Accept", "application/json"}
    ]
  end

  defp handle_json_error({:error, reason} = error) do
    AppLogger.api_error("JSON decode error", error: inspect(reason))
    error
  end
end
