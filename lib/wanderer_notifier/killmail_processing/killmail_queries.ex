defmodule WandererNotifier.KillmailProcessing.KillmailQueries do
  @moduledoc """
  DEPRECATED: This module is deprecated and will be removed in a future version.

  Please use WandererNotifier.Killmail.Queries.KillmailQueries instead.

  Database query functions for killmails.

  This module provides a clean interface for retrieving killmails from the database.
  It abstracts the details of the data access layer (Ash Resources) and provides
  a simpler API for common killmail queries.

  ## Usage

  ```elixir
  # Check if a killmail exists
  if KillmailQueries.exists?(12345) do
    # Handle existing killmail
  end

  # Get a killmail by ID
  case KillmailQueries.get(12345) do
    {:ok, killmail} -> # Process the killmail
    {:error, :not_found} -> # Handle not found
  end

  # Get character involvements for a killmail
  {:ok, involvements} = KillmailQueries.get_involvements(12345)

  # Find killmails for a character in a date range
  {:ok, killmails} = KillmailQueries.find_by_character(
    character_id,
    start_date,
    end_date,
    limit: 10
  )
  ```
  """

  @deprecated "Use WandererNotifier.Killmail.Queries.KillmailQueries instead"

  alias WandererNotifier.Killmail.Queries.KillmailQueries, as: NewKillmailQueries

  @doc """
  Checks if a killmail exists in the database by its ID.

  DEPRECATED: Use WandererNotifier.Killmail.Queries.KillmailQueries.exists?/1 instead.

  ## Parameters

  - `killmail_id`: The killmail ID to check (can be integer or UUID string)

  ## Returns

  - `true` if the killmail exists
  - `false` if the killmail does not exist or an error occurred

  ## Examples

      iex> exists?(12345)
      true

      iex> exists?(99999)
      false
  """
  @deprecated "Use WandererNotifier.Killmail.Queries.KillmailQueries.exists?/1 instead"
  @spec exists?(integer() | String.t()) :: boolean()
  def exists?(killmail_id) do
    NewKillmailQueries.exists?(killmail_id)
  end

  @doc """
  Gets a killmail by its ID.

  DEPRECATED: Use WandererNotifier.Killmail.Queries.KillmailQueries.get/1 instead.

  ## Parameters

  - `killmail_id`: The killmail ID to get (can be integer or UUID string)

  ## Returns

  - `{:ok, killmail}` if the killmail was found
  - `{:error, :not_found}` if the killmail was not found
  - `{:error, reason}` for other errors

  ## Examples

      iex> get(12345)
      {:ok, %KillmailResource{killmail_id: 12345, ...}}

      iex> get(99999)
      {:error, :not_found}
  """
  @deprecated "Use WandererNotifier.Killmail.Queries.KillmailQueries.get/1 instead"
  def get(killmail_id) do
    NewKillmailQueries.get(killmail_id)
  end

  @doc """
  Gets character involvements for a killmail.

  DEPRECATED: Use WandererNotifier.Killmail.Queries.KillmailQueries.get_involvements/1 instead.

  ## Parameters

  - `killmail_id`: The killmail ID to get involvements for (must be an integer)

  ## Returns

  - `{:ok, involvements}` with a list of KillmailCharacterInvolvement records
  - `{:error, :not_found}` if the killmail was not found
  - `{:error, reason}` for other errors

  ## Examples

      iex> get_involvements(12345)
      {:ok, [%KillmailCharacterInvolvement{...}, ...]}

      iex> get_involvements(99999)
      {:error, :not_found}
  """
  @deprecated "Use WandererNotifier.Killmail.Queries.KillmailQueries.get_involvements/1 instead"
  def get_involvements(killmail_id) when is_integer(killmail_id) do
    NewKillmailQueries.get_involvements(killmail_id)
  end

  # Add an overload that handles string input by parsing to integer
  def get_involvements(killmail_id) when is_binary(killmail_id) do
    NewKillmailQueries.get_involvements(killmail_id)
  end

  # Catch-all for any other type
  def get_involvements(killmail_id) do
    NewKillmailQueries.get_involvements(killmail_id)
  end

  @doc """
  Finds killmails involving a specific character in a date range.

  DEPRECATED: Use WandererNotifier.Killmail.Queries.KillmailQueries.find_by_character/4 instead.

  ## Parameters

  - `character_id`: Character ID to find killmails for
  - `start_date`: Start date for the query (inclusive)
  - `end_date`: End date for the query (inclusive)
  - `opts`: Options for the query
    - `:limit` - Maximum number of results (default: 100)
    - `:offset` - Offset for pagination (default: 0)
    - `:role` - Filter by role ("attacker" or "victim", default: both)

  ## Returns

  - `{:ok, killmails}` with a list of KillmailResource records
  - `{:error, reason}` for errors

  ## Examples

      # Get all killmails for a character in a date range
      iex> find_by_character(12345, ~U[2023-01-01 00:00:00Z], ~U[2023-01-31 23:59:59Z])
      {:ok, [%KillmailResource{...}, ...]}

      # Get only killmails where the character was a victim, with a limit
      iex> find_by_character(12345, start_date, end_date, limit: 10, role: "victim")
      {:ok, [%KillmailResource{...}, ...]}
  """
  @deprecated "Use WandererNotifier.Killmail.Queries.KillmailQueries.find_by_character/4 instead"
  def find_by_character(character_id, start_date, end_date, opts \\ []) do
    NewKillmailQueries.find_by_character(character_id, start_date, end_date, opts)
  end
end
