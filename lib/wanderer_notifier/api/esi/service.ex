defmodule WandererNotifier.Api.ESI.Service do
  @moduledoc """
  Service for accessing EVE Online ESI data.
  Provides higher-level functions for retrieving and processing game data.
  """
  require Logger
  alias WandererNotifier.Api.ESI.Client, as: ESIClient

  def get_esi_kill_mail(kill_id, killmail_hash, _opts \\ []) do
    ESIClient.get_killmail(kill_id, killmail_hash)
  end

  def get_character_info(eve_id, _opts \\ []) do
    ESIClient.get_character_info(eve_id)
  end

  def get_corporation_info(eve_id, _opts \\ []) do
    ESIClient.get_corporation_info(eve_id)
  end

  def get_alliance_info(eve_id, _opts \\ []) do
    ESIClient.get_alliance_info(eve_id)
  end

  def get_ship_type_name(ship_type_id, _opts \\ []) do
    ESIClient.get_universe_type(ship_type_id)
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
end
