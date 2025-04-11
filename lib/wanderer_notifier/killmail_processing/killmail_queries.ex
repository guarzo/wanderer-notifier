defmodule WandererNotifier.KillmailProcessing.KillmailQueries do
  @moduledoc """
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

  require Ash.Query

  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailCharacterInvolvement

  # Get configured API implementation - allows for mocking in tests
  defp api,
    do: Application.get_env(:wanderer_notifier, :resources_api, WandererNotifier.Resources.Api)

  @doc """
  Checks if a killmail exists in the database by its ID.

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
  @spec exists?(integer() | String.t()) :: boolean()
  def exists?(killmail_id) do
    # Determine if we're dealing with a UUID or an integer killmail_id
    is_uuid =
      is_binary(killmail_id) &&
        String.match?(
          killmail_id,
          ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        )

    # Build appropriate query based on the format of the ID
    query =
      if is_uuid do
        # UUID format - search by record ID
        KillmailResource
        |> Ash.Query.filter(id == ^killmail_id)
        |> Ash.Query.select([:id])
        |> Ash.Query.limit(1)
      else
        # Numeric killmail_id - convert to integer if it's a string
        killmail_id_int =
          case killmail_id do
            id when is_integer(id) ->
              id

            id when is_binary(id) ->
              case Integer.parse(id) do
                {int_id, _} -> int_id
                # keep as is if we can't parse it
                _ -> id
              end

            # any other type, keep as is
            id ->
              id
          end

        KillmailResource
        |> Ash.Query.filter(killmail_id == ^killmail_id_int)
        |> Ash.Query.select([:id])
        |> Ash.Query.limit(1)
      end

    # Perform the query
    case api().read(query) do
      {:ok, [_record]} -> true
      _ -> false
    end
  end

  @doc """
  Gets a killmail by its ID.

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
  @spec get(integer() | String.t()) :: {:ok, KillmailResource.t()} | {:error, any()}
  def get(killmail_id) do
    # Determine if we're dealing with a UUID or an integer killmail_id
    is_uuid =
      is_binary(killmail_id) &&
        String.match?(
          killmail_id,
          ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        )

    # Build appropriate query based on the format of the ID
    query =
      if is_uuid do
        # UUID format - search by record ID
        KillmailResource
        |> Ash.Query.filter(id == ^killmail_id)
        |> Ash.Query.limit(1)
      else
        # Numeric killmail_id - convert to integer if it's a string
        killmail_id_int =
          case killmail_id do
            id when is_integer(id) ->
              id

            id when is_binary(id) ->
              case Integer.parse(id) do
                {int_id, _} -> int_id
                # keep as is if we can't parse it
                _ -> id
              end

            # any other type, keep as is
            id ->
              id
          end

        KillmailResource
        |> Ash.Query.filter(killmail_id == ^killmail_id_int)
        |> Ash.Query.limit(1)
      end

    # Perform the query
    case api().read(query) do
      {:ok, [record]} -> {:ok, record}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Gets character involvements for a killmail.

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
  @spec get_involvements(integer()) ::
          {:ok, list(KillmailCharacterInvolvement.t())} | {:error, any()}
  def get_involvements(killmail_id) when is_integer(killmail_id) do
    # First check if the killmail exists
    if exists?(killmail_id) do
      # Then get all involvements for that killmail
      case api().read(
             KillmailCharacterInvolvement
             |> Ash.Query.filter(killmail.killmail_id == ^killmail_id)
             |> Ash.Query.load(:killmail)
           ) do
        {:ok, involvements} -> {:ok, involvements}
        error -> error
      end
    else
      {:error, :not_found}
    end
  end

  # Add an overload that handles string input by parsing to integer
  def get_involvements(killmail_id) when is_binary(killmail_id) do
    case Integer.parse(killmail_id) do
      {int_id, ""} ->
        # Only accept strings that are purely integers
        get_involvements(int_id)

      _ ->
        # Reject UUIDs and other non-integer strings
        {:error, {:invalid_id_format, "Expected integer killmail_id, got: #{killmail_id}"}}
    end
  end

  # Catch-all for any other type
  def get_involvements(killmail_id) do
    {:error, {:invalid_id_format, "Expected integer killmail_id, got: #{inspect(killmail_id)}"}}
  end

  @doc """
  Finds killmails involving a specific character in a date range.

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
  @spec find_by_character(integer(), DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, list(KillmailResource.t())} | {:error, any()}
  def find_by_character(character_id, start_date, end_date, opts \\ []) do
    # Set default options
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    role = Keyword.get(opts, :role, nil)

    # Build query
    query =
      KillmailCharacterInvolvement
      |> Ash.Query.filter(character_id == ^character_id)
      |> Ash.Query.filter(killmail.kill_time >= ^start_date)
      |> Ash.Query.filter(killmail.kill_time <= ^end_date)
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> Ash.Query.load(:killmail)

    # Add role filter if specified
    query =
      if role do
        Ash.Query.filter(query, character_role == ^role)
      else
        query
      end

    case api().read(query) do
      {:ok, involvements} ->
        # Extract the loaded killmails
        killmails = Enum.map(involvements, & &1.killmail)
        # Filter out nil values (shouldn't happen, but just in case)
        killmails = Enum.reject(killmails, &is_nil/1)
        {:ok, killmails}

      error ->
        error
    end
  end
end
