defmodule ChainKills.ESI.Client do
  @moduledoc """
  Minimal client for accessing ESI endpoints.
  """
  require Logger
  alias ChainKills.Http.Client, as: HttpClient

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  @base_url "https://esi.evetech.net/latest"

  @doc """
  Fetches a killmail from ESI.
  """
  def get_killmail(kill_id, hash) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    headers = default_headers()
    curl_example = HttpClient.build_curl_command("GET", url, headers)

    Logger.debug("[ESI] Fetching killmail => #{url}")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, true} ->
            Logger.error("[ESI] Unexpected 'true' from ESI for kill #{kill_id}/#{hash}. Curl: #{curl_example}")
            {:error, :esi_returned_true}
          {:ok, data} ->
            {:ok, data}
          {:error, decode_err} ->
            Logger.error("[ESI] JSON decode error for kill #{kill_id}/#{hash}: #{inspect(decode_err)}. Curl: #{curl_example}")
            {:error, decode_err}
        end

      {:ok, %{status_code: status, body: _body}} ->
        Logger.error("[ESI] Unexpected status #{status} for kill #{kill_id}/#{hash}. Curl: #{curl_example}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("[ESI] HTTP error for kill #{kill_id}/#{hash}: #{inspect(reason)}. Curl: #{curl_example}")
        {:error, reason}
    end
  end

  @doc """
  Fetches character info from ESI.
  """
  def get_character_info(eve_id) do
    url = "#{@base_url}/characters/#{eve_id}/"
    headers = default_headers()
    curl_example = HttpClient.build_curl_command("GET", url, headers)

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            {:ok, Map.put(data, "eve_id", eve_id)}
          {:error, decode_err} ->
            Logger.error("[ESI] JSON decode error for character #{eve_id}: #{inspect(decode_err)}. Curl: #{curl_example}")
            {:error, decode_err}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("[ESI] Unexpected status #{status} for character #{eve_id}. Curl: #{curl_example}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("[ESI] HTTP error fetching character #{eve_id}: #{inspect(reason)}. Curl: #{curl_example}")
        {:error, reason}
    end
  end

  @doc """
  Fetches corporation info from ESI.
  """
  def get_corporation_info(eve_id) do
    url = "#{@base_url}/corporations/#{eve_id}/"
    headers = default_headers()
    curl_example = HttpClient.build_curl_command("GET", url, headers)

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            {:ok, Map.put(data, "eve_id", eve_id)}
          {:error, decode_err} ->
            Logger.error("[ESI] JSON decode error for corporation #{eve_id}: #{inspect(decode_err)}. Curl: #{curl_example}")
            {:error, decode_err}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("[ESI] Unexpected status #{status} for corporation #{eve_id}. Curl: #{curl_example}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("[ESI] HTTP error fetching corporation #{eve_id}: #{inspect(reason)}. Curl: #{curl_example}")
        {:error, reason}
    end
  end

  @doc """
  Fetches alliance info from ESI.
  """
  def get_alliance_info(eve_id) do
    url = "#{@base_url}/alliances/#{eve_id}/"
    headers = default_headers()
    curl_example = HttpClient.build_curl_command("GET", url, headers)

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            {:ok, Map.put(data, "eve_id", eve_id)}
          {:error, decode_err} ->
            Logger.error("[ESI] JSON decode error for alliance #{eve_id}: #{inspect(decode_err)}. Curl: #{curl_example}")
            {:error, decode_err}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("[ESI] Unexpected status #{status} for alliance #{eve_id}. Curl: #{curl_example}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("[ESI] HTTP error fetching alliance #{eve_id}: #{inspect(reason)}. Curl: #{curl_example}")
        {:error, reason}
    end
  end

  defp default_headers do
    [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"}
    ]
  end
end
