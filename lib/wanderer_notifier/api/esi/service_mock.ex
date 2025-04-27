defmodule WandererNotifier.Api.ESI.ServiceMock do
  @moduledoc """
  DEPRECATED: Please use WandererNotifier.ESI.ServiceMock instead.

  Mock implementation of the ESI service for testing.
  Delegates to WandererNotifier.ESI.ServiceMock for all functionality.
  """

  alias WandererNotifier.ESI.ServiceMock, as: NewESIServiceMock

  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_killmail(kill_id, hash) do
    NewESIServiceMock.get_killmail(kill_id, hash)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character_info(character_id, opts \\ []) do
    NewESIServiceMock.get_character_info(character_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_corporation_info(corporation_id, opts \\ []) do
    NewESIServiceMock.get_corporation_info(corporation_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_alliance_info(alliance_id, opts \\ []) do
    NewESIServiceMock.get_alliance_info(alliance_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl true
  def get_ship_type_name(ship_type_id, opts \\ []) do
    NewESIServiceMock.get_ship_type_name(ship_type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type_info(type_id, opts \\ []) do
    NewESIServiceMock.get_type_info(type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  def search_inventory_type(query, strict \\ true, opts \\ []) do
    {:ok, %{"inventory_type" => [123_456]}}
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  def get_solar_system_name(system_id, opts \\ []) do
    NewESIServiceMock.get_system(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []) do
    NewESIServiceMock.get_system_info(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system(system_id, opts \\ []) do
    NewESIServiceMock.get_system(system_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []) do
    NewESIServiceMock.get_character(character_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    NewESIServiceMock.get_type(type_id, opts)
  end

  @deprecated "Use WandererNotifier.ESI.ServiceMock instead"
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit \\ 50, opts \\ []) do
    NewESIServiceMock.get_system_kills(system_id, limit, opts)
  end
end
