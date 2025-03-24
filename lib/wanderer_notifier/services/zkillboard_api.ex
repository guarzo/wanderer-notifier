defmodule WandererNotifier.Services.ZKillboardApi do
  @moduledoc """
  Service for interacting with the zKillboard API.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @base_url "https://zkillboard.com/api"

  @doc """
  Gets kills for a specific character within a date range.

  ## Parameters
    - character_id: The character ID to get kills for
    - start_str: Start date string in format "YYYYMMDDHHmm"
    - end_str: End date string in format "YYYYMMDDHHmm"

  ## Returns
    {:ok, kills} | {:error, reason}
  """
  def get_character_kills(character_id, start_str, end_str) do
    # Since startTime/endTime are no longer supported, we'll get recent kills and filter them
    url = "#{@base_url}/characterID/#{character_id}/"

    case HTTPoison.get(url, get_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, kills} when is_list(kills) ->
            # Parse the date strings once - format them into ISO8601 first
            AppLogger.api_debug("Converting date strings to ISO8601", %{
              start_str: start_str,
              end_str: end_str
            })

            # Convert YYYYMMDDHHmm to YYYY-MM-DDTHH:mm:00Z
            start_iso = format_to_iso8601(start_str)
            end_iso = format_to_iso8601(end_str)

            AppLogger.api_debug("Converted to ISO8601", %{
              start_iso: start_iso,
              end_iso: end_iso
            })

            case {DateTime.from_iso8601(start_iso), DateTime.from_iso8601(end_iso)} do
              {{:ok, start_date, _}, {:ok, end_date, _}} ->
                # Filter kills by date
                filtered_kills =
                  Enum.filter(kills, fn kill ->
                    case DateTime.from_iso8601(kill["killmail_time"]) do
                      {:ok, kill_date, _} ->
                        DateTime.compare(kill_date, start_date) in [:gt, :eq] and
                          DateTime.compare(kill_date, end_date) in [:lt, :eq]

                      _ ->
                        false
                    end
                  end)

                {:ok, filtered_kills}

              error ->
                AppLogger.api_error("Failed to parse date strings", %{
                  error: inspect(error),
                  start_str: start_str,
                  end_str: end_str,
                  start_iso: start_iso,
                  end_iso: end_iso
                })

                {:error, :invalid_date_format}
            end

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

  # Helper to format YYYYMMDDHHmm to ISO8601
  defp format_to_iso8601(date_str) do
    AppLogger.api_debug("Formatting date string to ISO8601", %{input: date_str})

    case date_str do
      <<year::binary-size(4), month::binary-size(2), day::binary-size(2), hour::binary-size(2),
        minute::binary-size(2)>> ->
        formatted = "#{year}-#{month}-#{day}T#{hour}:#{minute}:00Z"

        AppLogger.api_debug("Successfully formatted date", %{
          input: date_str,
          output: formatted,
          components: %{
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
          }
        })

        formatted

      _ ->
        AppLogger.api_error("Invalid date string format", %{input: date_str})
        raise ArgumentError, "Invalid date format. Expected YYYYMMDDHHmm"
    end
  end
end
