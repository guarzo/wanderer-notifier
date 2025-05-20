defmodule WandererNotifier.ESI.ClientBehaviour do
  @moduledoc """
  Behaviour for ESI client operations.
  Defines the contract that ESI client implementations must follow.
  """

  @type killmail_id :: String.t() | integer()
  @type hash :: String.t()
  @type response :: {:ok, map()} | {:error, term()}

  @callback get_killmail(killmail_id :: killmail_id, hash :: hash, opts :: keyword()) ::
              response
  @callback get_character_info(id :: integer(), opts :: keyword()) :: response
  @callback get_corporation_info(id :: integer(), opts :: keyword()) :: response
  @callback get_alliance_info(id :: integer(), opts :: keyword()) :: response
  @callback get_universe_type(type_id :: integer(), opts :: keyword()) :: response
  @callback get_system(system_id :: integer(), opts :: keyword()) :: response
  @callback get_system_kills(system_id :: integer(), limit :: integer(), opts :: keyword()) ::
              response
  @callback search_inventory_type(query :: String.t(), strict :: boolean()) :: response
end
