defmodule WandererNotifier.Api.ESI.Client do
  @moduledoc """
  DEPRECATED: Please use WandererNotifier.ESI.Client instead.

  Client for interacting with EVE Online's ESI (Swagger Interface) API.
  This module delegates to WandererNotifier.ESI.Client for all functionality.
  """

  alias WandererNotifier.ESI.Client, as: NewESIClient

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_killmail(kill_id, hash, opts \\ []) do
    NewESIClient.get_killmail(kill_id, hash, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_character_info(character_id, opts \\ []) do
    NewESIClient.get_character_info(character_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_corporation_info(corporation_id, opts \\ []) do
    NewESIClient.get_corporation_info(corporation_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_alliance_info(alliance_id, opts \\ []) do
    NewESIClient.get_alliance_info(alliance_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_universe_type(ship_type_id, opts \\ []) do
    NewESIClient.get_universe_type(ship_type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def search_inventory_type(query, strict) do
    NewESIClient.search_inventory_type(query, strict)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_solar_system(system_id, opts \\ []) do
    NewESIClient.get_solar_system(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Client instead"
  def get_system_kills(system_id, limit \\ 50, opts \\ []) do
    NewESIClient.get_system_kills(system_id, limit, opts)
  end
end
