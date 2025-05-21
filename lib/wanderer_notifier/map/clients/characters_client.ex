defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
  Client for fetching and caching character data from the EVE Online Map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def endpoint, do: "user-characters"

  @impl true
  def extract_data(%{"characters" => characters}) when is_list(characters) do
    {:ok, characters}
  end

  def extract_data(_) do
    AppLogger.api_error("Invalid characters data format")
    {:error, :invalid_format}
  end

  @impl true
  def validate_data(characters) when is_list(characters) do
    if Enum.all?(characters, &valid_character?/1) do
      :ok
    else
      AppLogger.api_error("Invalid character data found")
      {:error, :invalid_data}
    end
  end

  def validate_data(_) do
    AppLogger.api_error("Characters data is not a list")
    {:error, :invalid_data}
  end

  @impl true
  def process_data(new_characters, _cached_characters, _opts) do
    # For now, just return the new characters
    # In the future, we could implement diffing or other processing here
    {:ok, new_characters}
  end

  @impl true
  def cache_key, do: "map:characters"

  @impl true
  # 5 minutes
  def cache_ttl, do: 300

  defp valid_character?(%{
         "id" => id,
         "name" => name,
         "corporation_id" => corporation_id,
         "alliance_id" => alliance_id
       })
       when is_integer(id) and is_binary(name) and is_integer(corporation_id) and
              (is_integer(alliance_id) or is_nil(alliance_id)) do
    true
  end

  defp valid_character?(_), do: false
end
