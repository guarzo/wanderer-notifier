defmodule ChainKills.ESI.Client do
  @moduledoc """
  Low-level ESI client, using the Cacheable macro for caching.
  """
  require Logger
  require ChainKills.Cache.Cacheable
  alias ChainKills.Cache.Cacheable
  alias ChainKills.Http.Client, as: HttpClient

  @default_base_url "https://esi.evetech.net/latest"

  def base_url do
    Application.get_env(:chainkills, :esi_base_url, @default_base_url)
  end

  def get_killmail(kill_id, killmail_hash) do
    key = "esi:killmail:#{kill_id}:#{killmail_hash}"
    Cacheable.cacheable(key, 3600) do
      url = "#{base_url()}/killmails/#{kill_id}/#{killmail_hash}/"
      Logger.info("Fetching killmail from ESI: #{url}")

      do_http_get(url)
    end
  end

  def get_character_info(eve_id) do
    key = "esi:character:#{eve_id}"
    Cacheable.cacheable(key, 3600) do
      url = "#{base_url()}/characters/#{eve_id}/"
      Logger.info("Fetching character info from ESI: #{url}")

      do_http_get(url)
    end
  end

  def get_corporation_info(eve_id) do
    key = "esi:corporation:#{eve_id}"
    Cacheable.cacheable(key, 3600) do
      url = "#{base_url()}/corporations/#{eve_id}/"
      Logger.info("Fetching corporation info from ESI: #{url}")

      do_http_get(url)
    end
  end

  def get_alliance_info(eve_id) do
    key = "esi:alliance:#{eve_id}"
    Cacheable.cacheable(key, 3600) do
      url = "#{base_url()}/alliances/#{eve_id}/"
      Logger.info("Fetching alliance info from ESI: #{url}")

      do_http_get(url)
    end
  end

  defp do_http_get(url) do
    case HttpClient.get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          error ->
            Logger.error("Error decoding JSON: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Unexpected status code #{status} from ESI")
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        Logger.error("HTTP error fetching data from ESI: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
