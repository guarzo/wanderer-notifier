defmodule WandererNotifier.Api.ESI.ServiceBehaviour do
  @moduledoc """
  Behaviour specification for the ESI (EVE Swagger Interface) service.
  """

  @type killmail_id :: String.t()
  @type hash :: String.t()
  @type response :: {:ok, map()} | {:error, any()}

  @callback get_killmail(killmail_id, hash) :: response
  @callback get_character_info(character_id :: String.t()) :: response
  @callback get_corporation_info(corporation_id :: String.t() | integer()) :: response
  @callback get_alliance_info(alliance_id :: String.t() | integer()) :: response
  @callback get_system_info(system_id :: String.t() | integer()) :: response
  @callback get_type_info(type_id :: String.t() | integer()) :: response
end
