defmodule WandererNotifier.Killmail.WandererKillsAPI.Behaviour do
  @moduledoc """
  Behaviour definition for the WandererKills API client.

  This behaviour ensures type safety and allows for easy mocking in tests.
  Any implementation must provide these functions with the specified signatures.
  """

  @type killmail_id :: integer()
  @type system_id :: integer()
  @type character_id :: integer()
  @type killmail :: map()
  @type error_response :: {:error, %{type: atom(), message: String.t()}}

  @doc """
  Fetches killmails for a single system.
  """
  @callback fetch_system_killmails(system_id(), hours :: integer(), limit :: integer()) ::
              {:ok, [killmail()]} | error_response()

  @doc """
  Fetches killmails for multiple systems.
  """
  @callback fetch_systems_killmails(
              [system_id()],
              hours :: integer(),
              limit_per_system :: integer()
            ) ::
              {:ok, %{system_id() => [killmail()]}} | error_response()

  @doc """
  Gets a specific killmail by ID.
  """
  @callback get_killmail(killmail_id()) ::
              {:ok, killmail()} | error_response()

  @doc """
  Subscribes to killmail updates.
  """
  @callback subscribe_to_killmails(
              subscriber_id :: String.t(),
              [system_id()],
              callback_url :: String.t() | nil
            ) ::
              {:ok, subscription_id :: String.t()} | error_response()

  @doc """
  Fetches killmails for a specific character.
  """
  @callback fetch_character_killmails(character_id(), hours :: integer(), limit :: integer()) ::
              {:ok, [killmail()]} | error_response()
end
