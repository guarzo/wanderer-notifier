defmodule WandererNotifier.Map.Clients.SystemsClient do
  @moduledoc """
  Client for fetching and caching system data from the EVE Online Map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient

  @impl true
  def endpoint, do: "systems"

  @impl true
  def extract_data(%{"systems" => systems}), do: {:ok, systems}
  def extract_data(_), do: {:error, :invalid_data_format}

  @impl true
  def validate_data(systems) when is_list(systems) do
    if Enum.all?(systems, &valid_system?/1), do: :ok, else: {:error, :invalid_data}
  end

  def validate_data(_), do: {:error, :invalid_data}

  @impl true
  def process_data(new_systems, _cached_systems, _opts) do
    # For now, just return the new systems
    # In the future, we could implement diffing or other processing here
    {:ok, new_systems}
  end

  @impl true
  def cache_key, do: "map:systems"

  @impl true
  def cache_ttl, do: 300

  defp valid_system?(system) do
    is_map(system) and
      is_binary(system["name"]) and
      is_integer(system["id"]) and
      is_integer(system["constellation_id"]) and
      is_integer(system["region_id"])
  end
end
