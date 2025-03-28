defmodule WandererNotifier.Api.ESI.Service do
  @moduledoc """
  Service for accessing EVE Online ESI data.
  Provides higher-level functions for retrieving and processing game data.
  """
  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.ESI.Client, as: ESIClient

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_killmail(kill_id, killmail_hash) do
    AppLogger.api_debug("Fetching killmail from ESI", kill_id: kill_id, hash: killmail_hash)
    ESIClient.get_killmail(kill_id, killmail_hash)
  end

  # Legacy/backwards compatibility
  def get_esi_kill_mail(kill_id, killmail_hash, _opts \\ []) do
    AppLogger.api_debug("Using legacy killmail fetch method", kill_id: kill_id)
    get_killmail(kill_id, killmail_hash)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character_info(character_id, _opts \\ []) do
    ESIClient.get_character_info(character_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_corporation_info(corporation_id, _opts \\ []) do
    ESIClient.get_corporation_info(corporation_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_alliance_info(alliance_id, _opts \\ []) do
    ESIClient.get_alliance_info(alliance_id)
  end

  def get_ship_type_name(ship_type_id, _opts \\ []) do
    ESIClient.get_universe_type(ship_type_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type_info(type_id, _opts \\ []) do
    ESIClient.get_universe_type(type_id)
  end

  def search_inventory_type(query, strict \\ true, _opts \\ []) do
    ESIClient.search_inventory_type(query, strict)
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  def get_solar_system_name(system_id, _opts \\ []) do
    ESIClient.get_solar_system(system_id)
  end

  @doc """
  Alias for get_solar_system_name to maintain consistent naming.
  Fetches solar system info from ESI given a system_id.
  """
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []) do
    get_solar_system_name(system_id, opts)
  end

  @doc """
  Fetches region info from ESI given a region_id.
  Expects the response to include a "name" field.
  """
  def get_region_name(region_id, _opts \\ []) do
    ESIClient.get_region(region_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character(character_id) do
    get_character_info(character_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system(system_id) do
    get_system_info(system_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type(type_id) do
    get_type_info(type_id)
  end
end
