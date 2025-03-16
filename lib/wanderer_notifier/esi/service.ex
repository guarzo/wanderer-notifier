defmodule WandererNotifier.ESI.Service do
  @moduledoc """
  High-level ESI service for WandererNotifier.
  """
  require Logger
  alias WandererNotifier.ESI.Client

  def get_esi_kill_mail(kill_id, killmail_hash, _opts \\ []) do
    Client.get_killmail(kill_id, killmail_hash)
  end

  def get_character_info(eve_id, _opts \\ []) do
    Client.get_character_info(eve_id)
  end

  def get_corporation_info(eve_id, _opts \\ []) do
    Client.get_corporation_info(eve_id)
  end

  def get_alliance_info(eve_id, _opts \\ []) do
    Client.get_alliance_info(eve_id)
  end

  def get_ship_type_name(ship_type_id, _opts \\ []) do
    Client.get_universe_type(ship_type_id)
  end

  def search_inventory_type(query, strict \\ true, _opts \\ []) do
    Client.search_inventory_type(query, strict)
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  def get_solar_system_name(system_id, _opts \\ []) do
    Client.get_solar_system(system_id)
  end

  @doc """
  Fetches region info from ESI given a region_id.
  Expects the response to include a "name" field.
  """
  def get_region_name(region_id, _opts \\ []) do
    Client.get_region(region_id)
  end
end
