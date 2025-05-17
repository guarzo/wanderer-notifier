defmodule WandererNotifier.Killmail.ZKillClientBehaviour do
  @moduledoc """
  Behaviour for the ZKillboard API client.
  """

  @callback get_single_killmail(kill_id :: integer()) ::
              {:ok, map()} | {:error, any()}

  @callback get_recent_kills(limit :: integer()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_system_kills(system_id :: integer(), limit :: integer()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_character_kills(
              character_id :: integer(),
              date_range :: map() | nil,
              limit :: integer()
            ) :: {:ok, list(map())} | {:error, any()}
end
