defmodule WandererNotifier.ESI.ServiceMock do
  @moduledoc """
  Mock implementation of the ESI service for use in tests.
  """

  @behaviour WandererNotifier.ESI.ServiceBehaviour

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_killmail(kill_id, hash) do
    {:ok,
     %{
       "killmail_id" => kill_id,
       "hash" => hash,
       "solar_system_id" => 30_000_142,
       "victim" => %{"character_id" => "93300861", "corporation_id" => "1000107"},
       "attackers" => [%{"character_id" => "93300862", "corporation_id" => "1000108"}]
     }}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character_info(character_id, _opts \\ []) do
    {:ok,
     %{
       "character_id" => character_id,
       "name" => "Test Character #{character_id}",
       "corporation_id" => "1000107"
     }}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_corporation_info(corporation_id, _opts \\ []) do
    {:ok,
     %{
       "corporation_id" => corporation_id,
       "name" => "Test Corporation #{corporation_id}",
       "alliance_id" => "99000001"
     }}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_alliance_info(alliance_id, _opts \\ []) do
    {:ok,
     %{
       "alliance_id" => alliance_id,
       "name" => "Test Alliance #{alliance_id}"
     }}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_info(system_id, _opts \\ []) do
    {:ok,
     %{
       "system_id" => system_id,
       "name" => "Test System #{system_id}",
       "security_status" => 0.9,
       "constellation_id" => 20_000_001,
       "star_id" => 40_000_001
     }}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type_info(type_id, _opts \\ []) do
    {:ok,
     %{
       "type_id" => type_id,
       "name" => "Test Ship Type #{type_id}",
       "group_id" => 25
     }}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system(system_id, _opts \\ []) do
    get_system_info(system_id)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []) do
    get_character_info(character_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    get_type_info(type_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_ship_type_name(ship_type_id, _opts \\ []) do
    {:ok, %{"name" => "Test Ship #{ship_type_id}"}}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit, _opts \\ []) do
    kills =
      Enum.map(1..limit, fn i ->
        %{
          "system_id" => system_id,
          "ship_kills" => i,
          "npc_kills" => i * 2,
          "pod_kills" => i * 3
        }
      end)

    {:ok, Enum.take(kills, limit)}
  end
end
