defmodule WandererNotifier.Map.Clients.SystemsClient do
  @moduledoc """
  Client for fetching and caching system data from the EVE Online Map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.SystemStaticInfo
  alias WandererNotifier.Notifications.Determiner.System, as: SystemDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Cache.Keys, as: CacheKeys

  @impl true
  def endpoint, do: "systems"

  @impl true
  def extract_data(%{"data" => %{"systems" => systems}}) do
    {:ok, systems}
  end

  def extract_data(data) do
    AppLogger.api_error("Invalid systems data format",
      data: inspect(data)
    )

    {:error, :invalid_data_format}
  end

  @impl true
  def validate_data(systems) when is_list(systems) do
    if Enum.all?(systems, &valid_system?/1) do
      :ok
    else
      AppLogger.api_error("Systems data validation failed",
        count: length(systems)
      )

      {:error, :invalid_data}
    end
  end

  def validate_data(other) do
    AppLogger.api_error("Invalid systems data type",
      type: inspect(other)
    )

    {:error, :invalid_data}
  end

  @impl true
  def process_data(new_systems, _cached_systems, _opts) do
    AppLogger.api_info("Processing systems data",
      count: length(new_systems)
    )

    {:ok, new_systems}
  end

  @impl true
  def cache_key, do: CacheKeys.map_systems()

  @impl true
  def cache_ttl, do: WandererNotifier.Cache.Config.ttl_for(:map_data)

  @impl true
  def should_notify?(system_id, system) do
    SystemDeterminer.should_notify?(system_id, system)
  end

  @impl true
  def send_notification(system) do
    DiscordNotifier.send_new_system_notification(system)
  end

  @impl true
  def enrich_item(system) do
    case SystemStaticInfo.enrich_system(system) do
      {:ok, enriched} -> enriched
    end
  end

  defp valid_system?(system) do
    is_map(system) and
      valid_required_fields?(system) and
      valid_optional_fields?(system)
  end

  defp valid_required_fields?(system) do
    is_binary(system["name"]) and
      is_binary(system["id"]) and
      is_integer(system["solar_system_id"]) and
      is_boolean(system["locked"]) and
      is_boolean(system["visible"]) and
      is_integer(system["position_x"]) and
      is_integer(system["position_y"]) and
      is_integer(system["status"])
  end

  defp valid_optional_fields?(system) do
    valid_optional_string_field?(system["custom_name"]) and
      valid_optional_string_field?(system["description"]) and
      valid_optional_string_field?(system["original_name"]) and
      valid_optional_string_field?(system["temporary_name"]) and
      valid_optional_string_field?(system["tag"])
  end

  defp valid_optional_string_field?(field) do
    is_binary(field) or is_nil(field)
  end

  @doc """
  Fetches systems from the API and populates the cache.
  This is used during initialization to ensure we have system data.
  """
  def fetch_and_cache_systems do
    AppLogger.api_info("Fetching systems from API")
    fetch_and_cache()
  end
end
