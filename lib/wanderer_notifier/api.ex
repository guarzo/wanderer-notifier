defmodule WandererNotifier.API do
  @moduledoc """
  Proxy module for WandererNotifier.Api namespaced modules.
  Delegates API calls to the appropriate implementation modules.
  """

  alias WandererNotifier.Api.ZKill.Service, as: ZKillService
  alias WandererNotifier.Api.ESI.Service, as: ESIService

  @doc """
  Retrieves an enriched killmail by merging data from zKill and ESI.
  Delegates to WandererNotifier.Api.ZKill.Service.get_enriched_killmail/1.

  ## Examples

      iex> WandererNotifier.API.get_enriched_killmail(12345)
      {:ok, %{"killmail_id" => 12345, "zkb" => %{}, "esi_data" => %{...}}}

  Returns `{:ok, enriched_kill}` on success, or `{:error, reason}` on failure.
  """
  @spec get_enriched_killmail(any()) :: {:ok, map()} | {:error, any()}
  def get_enriched_killmail(kill_id) do
    ZKillService.get_enriched_killmail(kill_id)
  end

  @doc """
  Retrieves character information from ESI given an Eve ID.
  Delegates to WandererNotifier.Api.ESI.Service.get_character_info/1.

  ## Examples

      iex> WandererNotifier.API.get_character_info(987654)
      {:ok, %{"name" => "Character Name", "corporation_id" => 123, ...}}

  Returns `{:ok, character_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_character_info(integer()) :: {:ok, map()} | {:error, any()}
  def get_character_info(character_id) do
    ESIService.get_character_info(character_id)
  end

  @doc """
  Retrieves corporation information from ESI given a corporation ID.
  Delegates to WandererNotifier.Api.ESI.Service.get_corporation_info/1.

  ## Examples

      iex> WandererNotifier.API.get_corporation_info(123)
      {:ok, %{"name" => "Corporation Name", "ticker" => "CORP", ...}}

  Returns `{:ok, corporation_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_corporation_info(integer()) :: {:ok, map()} | {:error, any()}
  def get_corporation_info(corporation_id) do
    ESIService.get_corporation_info(corporation_id)
  end

  @doc """
  Retrieves alliance information from ESI given an alliance ID.
  Delegates to WandererNotifier.Api.ESI.Service.get_alliance_info/1.

  ## Examples

      iex> WandererNotifier.API.get_alliance_info(456)
      {:ok, %{"name" => "Alliance Name", "ticker" => "ALLY", ...}}

  Returns `{:ok, alliance_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_alliance_info(integer()) :: {:ok, map()} | {:error, any()}
  def get_alliance_info(alliance_id) do
    ESIService.get_alliance_info(alliance_id)
  end

  @doc """
  Retrieves ship type name from ESI given a type ID.
  Delegates to WandererNotifier.Api.ESI.Service.get_ship_type_name/1.

  ## Examples

      iex> WandererNotifier.API.get_ship_type_name(300)
      {:ok, "Titan"}

  Returns `{:ok, type_name}` on success, or `{:error, reason}` on failure.
  """
  @spec get_ship_type_name(integer()) :: {:ok, String.t()} | {:error, any()}
  def get_ship_type_name(type_id) do
    ESIService.get_ship_type_name(type_id)
  end

  @doc """
  Searches for inventory types by name.
  Delegates to WandererNotifier.Api.ESI.Service.search_inventory_type/1.

  ## Examples

      iex> WandererNotifier.API.search_inventory_type("Tritanium")
      {:ok, [34]}

  Returns `{:ok, [type_id]}` on success, or `{:error, reason}` on failure.
  """
  @spec search_inventory_type(String.t()) :: {:ok, [integer()]} | {:error, any()}
  def search_inventory_type(name) do
    ESIService.search_inventory_type(name)
  end

  @doc """
  Retrieves solar system name from ESI given a system ID.
  Delegates to WandererNotifier.Api.ESI.Service.get_solar_system_name/1.

  ## Examples

      iex> WandererNotifier.API.get_solar_system_name(30000142)
      {:ok, "Jita"}

  Returns `{:ok, system_name}` on success, or `{:error, reason}` on failure.
  """
  @spec get_solar_system_name(integer()) :: {:ok, String.t()} | {:error, any()}
  def get_solar_system_name(system_id) do
    ESIService.get_solar_system_name(system_id)
  end
end
