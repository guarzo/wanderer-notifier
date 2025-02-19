defmodule ChainKills.ZKill.Client do
  @moduledoc """
  ZKill client for fetching single killmails, with caching.
  """
  require Logger
  require ChainKills.Cache.Cacheable
  alias ChainKills.Cache.Cacheable
  alias ChainKills.Http.Client, as: HttpClient

  @default_base "https://zkillboard.com"
  @zkill_requests_per_sec 1
  @zkill_cache_expiration 86_400

  def get_single_killmail(kill_id) do
    key = "zkill:single:killID:#{kill_id}"
    Cacheable.cacheable(key, @zkill_cache_expiration) do
      url = "#{base_url()}/api/killID/#{kill_id}/"
      Logger.debug("ZKill: fetching single killmail from #{url}")
      :timer.sleep(div(1000, @zkill_requests_per_sec))

      case HttpClient.get(url) do
        {:ok, %{status_code: 200, body: body}} ->
          decode_kills(body)

        {:ok, %{status_code: status}} ->
          {:error, "Unexpected status: #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp base_url do
    Application.get_env(:chainkills, :zkill_base_url, @default_base)
  end

  defp decode_kills(body) do
    case Jason.decode(body) do
      {:ok, kills} when is_list(kills) ->
        if kills != [] do
          {:ok, hd(kills)}
        else
          {:error, :no_killmail_returned}
        end

      error ->
        Logger.error("Error decoding single killmail: #{inspect(error)}")
        {:error, error}
    end
  end
end
