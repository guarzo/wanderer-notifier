defmodule ChainKills.Map.Characters do
  @moduledoc """
  Tracked characters API calls.
  """
  require Logger
  alias ChainKills.Http.Client, as: HttpClient
  alias ChainKills.Cache.Repository, as: CacheRepo

  @characters_cache_ttl 300

  def update_tracked_characters do
    with {:ok, chars_url}  <- build_characters_url(),
         {:ok, body}       <- fetch_characters_body(chars_url),
         {:ok, json}       <- decode_json(body),
         {:ok, tracked}    <- process_characters(json)
    do
      CacheRepo.set("map:characters", tracked, @characters_cache_ttl)
      # Logger.info("[update_tracked_characters] fetched #{length(tracked)} tracked characters")
      {:ok, tracked}
    else
      {:error, msg} = err ->
        Logger.error("[update_tracked_characters] error: #{inspect(msg)}")
        err
    end
  end

  defp build_characters_url do
    case validate_map_env() do
      {:ok, map_url, map_name} ->
        {:ok, "#{map_url}/api/map/characters?slug=#{map_name}"}
      {:error, _} = err ->
        err
    end
  end

  # We need a Bearer token
  defp fetch_characters_body(url) do
    map_token = Application.get_env(:chainkills, :map_token)
    headers =
      if map_token do
        [{"Authorization", "Bearer " <> map_token}]
      else
        []
      end

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status_code: status}} ->
        {:error, "Unexpected status: #{status}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_json(raw) do
    case Jason.decode(raw) do
      {:ok, data} -> {:ok, data}
      error -> {:error, error}
    end
  end

  defp process_characters(%{"data" => data}) when is_list(data) do
    tracked =
      data
      |> Enum.filter(fn item -> Map.get(item, "tracked") == true end)
      |> Enum.map(fn item ->
        char_info = item["character"] || %{}
        %{
          "id"          => char_info["id"],
          "eve_id"      => char_info["eve_id"],
          "name"        => char_info["name"],
          "corp_id"     => char_info["corporation_id"],
          "alliance_id" => char_info["alliance_id"]
        }
      end)

    {:ok, tracked}
  end

  defp process_characters(_), do: {:ok, []}

  def validate_map_env do
    map_url  = Application.get_env(:chainkills, :map_url)
    map_name = Application.get_env(:chainkills, :map_name)

    if map_url in [nil, ""] or map_name in [nil, ""] do
      {:error, "map_url or map_name not configured"}
    else
      {:ok, map_url, map_name}
    end
  end
end
