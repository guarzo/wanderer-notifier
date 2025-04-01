defmodule WandererNotifier.Api.ESI.ServiceBehaviour do
  @moduledoc """
  Behaviour for the ESI API service.
  """

  @type killmail_id :: String.t()
  @type hash :: String.t()
  @type response :: {:ok, map()} | {:error, any()}

  @callback get_killmail(kill_id :: integer(), hash :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback get_character_info(character_id :: String.t()) :: response
  @callback get_corporation_info(corporation_id :: String.t() | integer()) :: response
  @callback get_alliance_info(alliance_id :: String.t() | integer()) :: response
  @callback get_system_info(system_id :: integer()) ::
              {:ok, map()} | {:error, term()}
  @callback get_type_info(type_id :: String.t() | integer()) :: response
  @callback get_system(system_id :: integer()) :: response
  @callback get_character(character_id :: integer()) :: {:ok, map()} | {:error, term()}
  @callback get_type(type_id :: integer()) :: {:ok, map()} | {:error, term()}
  @callback get_ship_type_name(ship_type_id :: integer()) :: {:ok, map()} | {:error, term()}
  @callback get_system_kills(system_id :: integer(), limit :: integer()) ::
              {:ok, list(map())} | {:error, term()}
end
