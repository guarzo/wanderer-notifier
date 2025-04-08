defmodule WandererNotifier.Killmail do
  @moduledoc """
  Central documentation and utility functions for working with killmails.

  ## Killmail Data Model

  Killmails are stored using two resources:

  1. `WandererNotifier.Resources.Killmail` - Stores the core killmail data
  2. `WandererNotifier.Resources.KillmailCharacterInvolvement` - Tracks which of your characters were involved

  ### Killmail Resource

  The Killmail resource holds the following information:

  - **Basic Metadata**: killmail_id, kill_time, processed_at
  - **Economic Data**: total_value, points, is_npc, is_solo
  - **System Information**: solar_system_id, solar_system_name, solar_system_security, region_id, region_name
  - **Victim Information**: victim_id, victim_name, victim_ship_id, victim_ship_name, victim_corporation_id, victim_corporation_name, victim_alliance_id, victim_alliance_name
  - **Basic Attacker Information**: attacker_count, final_blow_attacker_id, final_blow_attacker_name, final_blow_ship_id, final_blow_ship_name
  - **Raw Data**: zkb_hash, full_victim_data, full_attacker_data

  ### KillmailCharacterInvolvement Resource

  The KillmailCharacterInvolvement resource tracks how each character was involved in a killmail:

  - **Relationship**: References the killmail
  - **Character Information**: character_id, character_role (attacker or victim)
  - **Ship Information**: ship_type_id, ship_type_name
  - **Combat Details**: damage_done, is_final_blow, weapon_type_id, weapon_type_name

  ## Example Usage

  ```elixir
  # Get a specific killmail
  {:ok, [killmail]} = Api.read(Killmail |> Query.filter(killmail_id == 12345))

  # Get all kills for a character
  query =
    KillmailCharacterInvolvement
    |> Query.filter(character_id == 67890)
    |> Query.filter(character_role == :attacker)
    |> Query.load(:killmail)

  {:ok, involvements} = Api.read(query)
  kills = Enum.map(involvements, & &1.killmail)

  # Get a character's kills in a specific system
  query =
    KillmailCharacterInvolvement
    |> Query.filter(character_id == 67890)
    |> Query.filter(character_role == :attacker)
    |> Query.load(:killmail)
    |> Query.filter(killmail.solar_system_id == 30000142)

  {:ok, involvements} = Api.read(query)
  jita_kills = Enum.map(involvements, & &1.killmail)

  # Get a character's total kill value in a time period
  start_date = ~U[2023-01-01 00:00:00Z]
  end_date = ~U[2023-01-31 23:59:59Z]

  query =
    KillmailCharacterInvolvement
    |> Query.filter(character_id == 67890)
    |> Query.filter(character_role == :attacker)
    |> Query.load(:killmail)
    |> Query.filter(killmail.kill_time >= ^start_date)
    |> Query.filter(killmail.kill_time <= ^end_date)

  {:ok, involvements} = Api.read(query)
  kills = Enum.map(involvements, & &1.killmail)
  total_value = Enum.reduce(kills, Decimal.new(0), fn km, acc ->
    Decimal.add(acc, km.total_value || Decimal.new(0))
  end)
  ```

  ## Common Query Patterns

  ### Finding Specific Killmails

  ```elixir
  # Find a kill by ID
  Killmail |> Query.filter(killmail_id == ^kill_id)

  # Find kills in a specific system
  Killmail |> Query.filter(solar_system_id == ^system_id)

  # Find high-value kills
  Killmail |> Query.filter(total_value >= ^min_value) |> Query.sort(total_value: :desc)
  ```

  ### Character Involvement Queries

  ```elixir
  # All kills a character was involved in
  KillmailCharacterInvolvement
  |> Query.filter(character_id == ^char_id)
  |> Query.load(:killmail)

  # Get final blows by a character
  KillmailCharacterInvolvement
  |> Query.filter(character_id == ^char_id)
  |> Query.filter(is_final_blow == true)
  |> Query.load(:killmail)
  ```

  ## Migration Notes

  This normalized data model replaces the previous approach that used:

  1. `WandererNotifier.Data.Killmail` - A simple struct with raw data
  2. `WandererNotifier.Resources.Killmail` - A denormalized Ash resource

  The new normalized model provides:

  - Proper data normalization (each killmail is stored once)
  - Explicit tracking of character involvement
  - Better query performance for common patterns
  - Reduced database storage requirements
  - Improved data consistency

  During the transition period, compatibility functions are provided to work with both models.
  """

  require Ash.Query

  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.KillmailCharacterInvolvement

  @doc """
  Checks if a killmail exists in the database by its ID.

  ## Parameters
  - killmail_id: The EVE Online killmail ID to check

  ## Returns
  - true if the killmail exists in the database
  - false if it does not exist
  """
  def exists?(killmail_id) do
    case Api.read(
           Killmail
           |> Ash.Query.filter(killmail_id == ^killmail_id)
           |> Ash.Query.select([:id])
           |> Ash.Query.limit(1)
         ) do
      {:ok, [_record]} -> true
      _ -> false
    end
  end

  @doc """
  Gets a killmail by its ID.

  ## Parameters
  - killmail_id: The EVE Online killmail ID

  ## Returns
  - {:ok, killmail} if found
  - {:error, :not_found} if not found
  """
  def get(killmail_id) do
    case Api.read(
           Killmail
           |> Ash.Query.filter(killmail_id == ^killmail_id)
           |> Ash.Query.limit(1)
         ) do
      {:ok, [killmail]} -> {:ok, killmail}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Gets all character involvements for a killmail.

  ## Parameters
  - killmail_id: The EVE Online killmail ID

  ## Returns
  - {:ok, involvements} with a list of involvements
  - {:error, :not_found} if killmail not found
  """
  def get_involvements(killmail_id) do
    case exists?(killmail_id) do
      true ->
        Api.read(
          KillmailCharacterInvolvement
          |> Ash.Query.filter(killmail.killmail_id == ^killmail_id)
        )

      false ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds all killmails involving a character within a date range.

  ## Parameters
  - character_id: The character ID to search for
  - start_date: The beginning of the date range (DateTime)
  - end_date: The end of the date range (DateTime)
  - opts: Additional options
    - :role - Filter by character role (:attacker or :victim)
    - :limit - Maximum number of results to return (default: 100)
    - :sort - Sort direction for kill_time (:asc or :desc, default: :desc)

  ## Returns
  - {:ok, killmails} with the list of killmail records
  - {:error, reason} if the query fails
  """
  def find_by_character(character_id, start_date, end_date, opts \\ []) do
    role = Keyword.get(opts, :role)
    limit = Keyword.get(opts, :limit, 100)
    sort_dir = Keyword.get(opts, :sort, :desc)

    query =
      KillmailCharacterInvolvement
      |> Ash.Query.filter(character_id == ^character_id)
      |> then(fn q ->
        if role, do: Ash.Query.filter(q, character_role == ^role), else: q
      end)
      |> Ash.Query.load(:killmail)
      |> Ash.Query.filter(killmail.kill_time >= ^start_date)
      |> Ash.Query.filter(killmail.kill_time <= ^end_date)
      |> Ash.Query.sort({:expr, [:killmail, :kill_time]}, sort_dir)
      |> Ash.Query.limit(limit)

    case Api.read(query) do
      {:ok, involvements} ->
        killmails = Enum.map(involvements, & &1.killmail)
        {:ok, killmails}

      error ->
        error
    end
  end

  @doc """
  Gets a field from a killmail structure.

  ## Parameters
  - killmail: The killmail data
  - field: The field name to retrieve
  - default: Default value if the field is not found (default: nil)

  ## Returns
  - The value of the field or the default value
  """
  def get(killmail, field, default \\ nil) do
    cond do
      # Direct field access for resource model
      is_struct(killmail, Killmail) && Map.has_key?(killmail, String.to_atom(field)) ->
        Map.get(killmail, String.to_atom(field))

      # Direct field access for plain maps
      is_map(killmail) && Map.has_key?(killmail, field) ->
        Map.get(killmail, field)

      # Try string key for maps
      is_map(killmail) && Map.has_key?(killmail, String.to_atom(field)) ->
        Map.get(killmail, String.to_atom(field))

      true ->
        default
    end
  end

  @doc """
  Gets the system_id from a killmail.

  ## Parameters
  - killmail: The killmail data

  ## Returns
  - The system_id or nil if not found
  """
  def get_system_id(killmail) do
    if is_struct(killmail, Killmail) && Map.has_key?(killmail, :solar_system_id) do
      killmail.solar_system_id
    else
      nil
    end
  end

  @doc """
  Gets victim data from a killmail.

  ## Parameters
  - killmail: The killmail data

  ## Returns
  - The victim data as a map or empty map if not found
  """
  def get_victim(killmail) do
    if is_struct(killmail, Killmail) do
      if killmail.victim_id do
        %{
          "character_id" => killmail.victim_id,
          "character_name" => killmail.victim_name,
          "ship_type_id" => killmail.victim_ship_id,
          "ship_type_name" => killmail.victim_ship_name,
          "corporation_id" => killmail.victim_corporation_id,
          "corporation_name" => killmail.victim_corporation_name,
          "alliance_id" => killmail.victim_alliance_id,
          "alliance_name" => killmail.victim_alliance_name
        }
      else
        # Try the full_victim_data if available
        killmail.full_victim_data || %{}
      end
    else
      %{}
    end
  end

  @doc """
  Gets attacker data from a killmail.

  ## Parameters
  - killmail: The killmail data

  ## Returns
  - The attacker data as a list or empty list if not found
  """
  def get_attacker(killmail) do
    if is_struct(killmail, Killmail) && Map.has_key?(killmail, :full_attacker_data) do
      killmail.full_attacker_data || []
    else
      []
    end
  end

  @doc """
  Finds a specific field in a killmail structure for a character.

  ## Parameters
  - killmail: The killmail data
  - field: The field name to retrieve
  - character_id: The character ID to look for
  - role: The role of the character (:attacker or :victim)

  ## Returns
  - The value of the field or nil if not found
  """
  def find_field(killmail, field, character_id, role) do
    case role do
      :victim ->
        victim = get_victim(killmail)

        if to_string(Map.get(victim, "character_id", "")) == to_string(character_id) do
          Map.get(victim, field)
        else
          nil
        end

      :attacker ->
        attackers = get_attacker(killmail)

        attacker =
          Enum.find(attackers, fn a ->
            to_string(Map.get(a, "character_id", "")) == to_string(character_id)
          end)

        if attacker, do: Map.get(attacker, field), else: nil

      _ ->
        nil
    end
  end

  @doc """
  Gets debug data from a killmail structure for troubleshooting.

  ## Parameters
  - killmail: The killmail data

  ## Returns
  - A map of useful debug information
  """
  def debug_data(killmail) do
    %{
      # Basic identification
      struct_type: if(is_struct(killmail), do: killmail.__struct__, else: :not_struct),
      killmail_id: if(is_struct(killmail, Killmail), do: killmail.killmail_id, else: nil),

      # Check for key data structures
      has_victim_data: not is_nil(get_victim(killmail)),
      has_attacker_data: not Enum.empty?(get_attacker(killmail) || []),

      # System information
      system_id: get_system_id(killmail),
      system_name: get(killmail, "solar_system_name"),

      # Attacker count
      attacker_count: if(is_struct(killmail, Killmail), do: killmail.attacker_count, else: 0)
    }
  end

  @doc """
  Validates that a killmail has complete data for processing.

  ## Parameters
  - killmail: The killmail data

  ## Returns
  - :ok if the killmail data is complete
  - {:error, reason} if data is missing
  """
  def validate_complete_data(killmail) do
    field_checks = [
      {:killmail_id, debug_data(killmail).killmail_id, "Killmail ID missing"},
      {:system_id, get_system_id(killmail), "Solar system ID missing"},
      {:system_name, get(killmail, "solar_system_name"), "Solar system name missing"},
      {:victim, get_victim(killmail), "Victim data missing"},
      {:has_valid_victim, not Enum.empty?(get_victim(killmail) || %{}),
       "Valid victim data missing"}
    ]

    # Find first failure
    case Enum.find(field_checks, fn {_, value, _} -> is_nil(value) || value == false end) do
      nil -> :ok
      {_, _, reason} -> {:error, reason}
    end
  end
end
