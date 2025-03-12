defmodule WandererNotifier.API do
  @moduledoc """
  A context module for interacting with external APIs used by WandererNotifier.

  This module provides functions to:
    - Retrieve an enriched killmail by merging data from zKill and ESI.
    - Retrieve character, corporation, alliance, and ship type information from ESI.
    - Search for inventory types via ESI.
    - Retrieve solar system information from ESI.
  """

  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.ZKill.Service, as: ZKillService

  @doc """
  Retrieves an enriched killmail by merging data from zKill and ESI.

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

  ## Examples

      iex> WandererNotifier.API.get_character_info(987654)
      {:ok, %{"eve_id" => 987654, "name" => "Some Character", ...}}

  Returns `{:ok, character_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_character_info(integer() | String.t()) :: {:ok, map()} | {:error, any()}
  def get_character_info(eve_id) do
    ESIService.get_character_info(eve_id)
  end

  @doc """
  Retrieves corporation information from ESI given an Eve ID.

  ## Examples

      iex> WandererNotifier.API.get_corporation_info(123)
      {:ok, %{"eve_id" => 123, "name" => "Some Corporation", ...}}

  Returns `{:ok, corporation_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_corporation_info(integer() | String.t()) :: {:ok, map()} | {:error, any()}
  def get_corporation_info(eve_id) do
    ESIService.get_corporation_info(eve_id)
  end

  @doc """
  Retrieves alliance information from ESI given an Eve ID.

  ## Examples

      iex> WandererNotifier.API.get_alliance_info(456)
      {:ok, %{"eve_id" => 456, "name" => "Some Alliance", ...}}

  Returns `{:ok, alliance_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_alliance_info(integer() | String.t()) :: {:ok, map()} | {:error, any()}
  def get_alliance_info(eve_id) do
    ESIService.get_alliance_info(eve_id)
  end

  @doc """
  Retrieves the ship type name from ESI given a ship type ID.

  ## Examples

      iex> WandererNotifier.API.get_ship_type_name(300)
      {:ok, %{"name" => "Battleship", ...}}

  Returns `{:ok, ship_type_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_ship_type_name(integer() | String.t()) :: {:ok, map()} | {:error, any()}
  def get_ship_type_name(ship_type_id) do
    ESIService.get_ship_type_name(ship_type_id)
  end

  @doc """
  Searches for inventory types via ESI using a search query.

  ## Examples

      iex> WandererNotifier.API.search_inventory_type("Tritanium")
      {:ok, %{"inventory_type" => [34, 35, ...]}}

  Returns `{:ok, result}` on success, or `{:error, reason}` on failure.
  """
  @spec search_inventory_type(String.t(), boolean()) :: {:ok, map()} | {:error, any()}
  def search_inventory_type(query, strict \\ true) do
    ESIService.search_inventory_type(query, strict)
  end

  @doc """
  Retrieves solar system information from ESI given a solar system ID.

  ## Examples

      iex> WandererNotifier.API.get_solar_system_name(30000142)
      {:ok, %{"name" => "Jita", ...}}

  Returns `{:ok, solar_system_info}` on success, or `{:error, reason}` on failure.
  """
  @spec get_solar_system_name(integer() | String.t()) :: {:ok, map()} | {:error, any()}
  def get_solar_system_name(system_id) do
    ESIService.get_solar_system_name(system_id)
  end
end
