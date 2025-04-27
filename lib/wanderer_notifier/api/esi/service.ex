defmodule WandererNotifier.Api.ESI.Service do
  @moduledoc """
  DEPRECATED: Please use WandererNotifier.ESI.Service instead.

  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  This module delegates to WandererNotifier.ESI.Service for all functionality.
  """

  require Logger
  alias WandererNotifier.ESI.Service, as: NewESIService

  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_killmail(kill_id, killmail_hash) do
    NewESIService.get_killmail(kill_id, killmail_hash)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character_info(character_id, opts \\ []) do
    NewESIService.get_character_info(character_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_corporation_info(corporation_id, opts \\ []) do
    NewESIService.get_corporation_info(corporation_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_alliance_info(alliance_id, opts \\ []) do
    NewESIService.get_alliance_info(alliance_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl true
  def get_ship_type_name(ship_type_id, opts \\ []) do
    NewESIService.get_ship_type_name(ship_type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type_info(type_id, opts \\ []) do
    NewESIService.get_type_info(type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  def search_inventory_type(query, strict \\ true, opts \\ []) do
    NewESIService.search_inventory_type(query, strict, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  def get_solar_system_name(system_id, opts \\ []) do
    NewESIService.get_system(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []) do
    NewESIService.get_system_info(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system(system_id, opts \\ []) do
    NewESIService.get_system(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []) do
    NewESIService.get_character(character_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    NewESIService.get_type(type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.Service instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit \\ 50, opts \\ []) do
    NewESIService.get_system_kills(system_id, limit, opts)
  end
end
