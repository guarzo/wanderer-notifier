defmodule WandererNotifier.KillmailProcessing.KillmailData do
  @moduledoc """
  Defines the in-memory structure for killmail data during processing.

  This struct provides a standardized representation of killmail data as it moves
  through various processing stages, regardless of its source. It ensures all
  components in the pipeline have a consistent view of the data.

  All data is stored at the top level for direct access, with minimal nesting.
  """

  @type t :: %__MODULE__{
          # Core identification
          killmail_id: integer(),
          zkb_hash: String.t() | nil,

          # Timestamps
          kill_time: DateTime.t() | nil,
          processed_at: DateTime.t() | nil,

          # System information
          solar_system_id: integer() | nil,
          solar_system_name: String.t() | nil,
          region_id: integer() | nil,
          region_name: String.t() | nil,
          solar_system_security: float() | nil,

          # Victim information
          victim_id: integer() | nil,
          victim_name: String.t() | nil,
          victim_ship_id: integer() | nil,
          victim_ship_name: String.t() | nil,
          victim_corporation_id: integer() | nil,
          victim_corporation_name: String.t() | nil,
          victim_alliance_id: integer() | nil,
          victim_alliance_name: String.t() | nil,

          # Attacker information
          attackers: list(map()) | nil,
          attacker_count: integer() | nil,
          final_blow_attacker_id: integer() | nil,
          final_blow_attacker_name: String.t() | nil,
          final_blow_ship_id: integer() | nil,
          final_blow_ship_name: String.t() | nil,

          # Economic data
          total_value: float() | nil,
          points: integer() | nil,
          is_npc: boolean(),
          is_solo: boolean(),

          # Status flags
          persisted: boolean(),

          # Raw data for reference (only used when needed)
          raw_zkb_data: map() | nil,
          raw_esi_data: map() | nil,

          # Processing metadata
          metadata: map()
        }

  defstruct [
    # Core identification
    :killmail_id,
    :zkb_hash,

    # Timestamps
    :kill_time,
    :processed_at,

    # System information
    :solar_system_id,
    :solar_system_name,
    :region_id,
    :region_name,
    :solar_system_security,

    # Victim information
    :victim_id,
    :victim_name,
    :victim_ship_id,
    :victim_ship_name,
    :victim_corporation_id,
    :victim_corporation_name,
    :victim_alliance_id,
    :victim_alliance_name,

    # Attacker information
    :attackers,
    :attacker_count,
    :final_blow_attacker_id,
    :final_blow_attacker_name,
    :final_blow_ship_id,
    :final_blow_ship_name,

    # Economic data
    :total_value,
    :points,

    # Raw data for reference
    :raw_zkb_data,
    :raw_esi_data,

    # Default values must come last as keyword pairs
    is_npc: false,
    is_solo: false,
    persisted: false,
    metadata: %{}
  ]

  @doc """
  Creates a KillmailData struct from zKillboard data and ESI API data.

  Extracts all relevant fields from both sources and places them at the top level
  for direct access, while preserving the raw data for reference if needed.

  ## Parameters

  - `zkb_data`: Raw data from zKillboard API
  - `esi_data`: Data from EVE Swagger Interface (ESI) API

  ## Returns

  A new KillmailData struct with data extracted from both sources

  ## Examples

      iex> zkb_data = %{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}
      iex> esi_data = %{"solar_system_id" => 30000142, "solar_system_name" => "Jita"}
      iex> KillmailData.from_zkb_and_esi(zkb_data, esi_data)
      %KillmailData{
        killmail_id: 12345,
        zkb_hash: "abc123",
        solar_system_id: 30000142,
        solar_system_name: "Jita",
        ...
      }
  """
  @spec from_zkb_and_esi(map(), map()) :: t() | {:error, String.t()}
  def from_zkb_and_esi(zkb_data, esi_data) do
    # Extract core identification
    with {:ok, killmail_id} <- extract_killmail_id(zkb_data),
         {:ok, zkb_hash} <- extract_zkb_hash(zkb_data) do
      # Extract system information
      system_id = extract_system_id(esi_data)
      system_name = Map.get(esi_data, "solar_system_name")

      # Extract timestamp
      kill_time = extract_kill_time(esi_data)
      processed_at = DateTime.utc_now()

      # Extract victim data
      victim = Map.get(esi_data, "victim") || %{}
      victim_id = Map.get(victim, "character_id")
      victim_name = Map.get(victim, "character_name")
      victim_ship_id = Map.get(victim, "ship_type_id")
      victim_ship_name = Map.get(victim, "ship_type_name")
      victim_corp_id = Map.get(victim, "corporation_id")
      victim_corp_name = Map.get(victim, "corporation_name")
      victim_alliance_id = Map.get(victim, "alliance_id")
      victim_alliance_name = Map.get(victim, "alliance_name")

      # Extract attacker data
      attackers = Map.get(esi_data, "attackers") || []
      attacker_count = length(attackers)

      # Find final blow attacker
      final_blow_attacker =
        Enum.find(attackers, fn attacker ->
          Map.get(attacker, "final_blow", false) == true
        end) || %{}

      final_blow_attacker_id = Map.get(final_blow_attacker, "character_id")
      final_blow_attacker_name = Map.get(final_blow_attacker, "character_name")
      final_blow_ship_id = Map.get(final_blow_attacker, "ship_type_id")
      final_blow_ship_name = Map.get(final_blow_attacker, "ship_type_name")

      # Extract economic data
      zkb = extract_zkb_section(zkb_data)
      total_value = Map.get(zkb, "totalValue")
      points = Map.get(zkb, "points")
      is_npc = Map.get(zkb, "npc", false)
      is_solo = Map.get(zkb, "solo", false)

      # Create the struct with all data at top level
      %__MODULE__{
        # Core identification
        killmail_id: killmail_id,
        zkb_hash: zkb_hash,

        # Timestamps
        kill_time: kill_time,
        processed_at: processed_at,

        # System information
        solar_system_id: system_id,
        solar_system_name: system_name,

        # Victim information
        victim_id: victim_id,
        victim_name: victim_name,
        victim_ship_id: victim_ship_id,
        victim_ship_name: victim_ship_name,
        victim_corporation_id: victim_corp_id,
        victim_corporation_name: victim_corp_name,
        victim_alliance_id: victim_alliance_id,
        victim_alliance_name: victim_alliance_name,

        # Attacker information
        attackers: attackers,
        attacker_count: attacker_count,
        final_blow_attacker_id: final_blow_attacker_id,
        final_blow_attacker_name: final_blow_attacker_name,
        final_blow_ship_id: final_blow_ship_id,
        final_blow_ship_name: final_blow_ship_name,

        # Economic data
        total_value: total_value,
        points: points,

        # Raw data for reference only
        raw_zkb_data: zkb_data,
        raw_esi_data: esi_data,

        # Flags and metadata
        is_npc: is_npc,
        is_solo: is_solo,
        persisted: false,
        metadata: %{}
      }
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a KillmailData struct from a KillmailResource entity.

  ## Parameters

  - `resource`: KillmailResource entity from the database

  ## Returns

  A KillmailData struct populated from the resource's fields

  ## Examples

      iex> resource = %KillmailResource{
      ...>   killmail_id: 12345,
      ...>   solar_system_id: 30000142,
      ...>   solar_system_name: "Jita"
      ...> }
      iex> KillmailData.from_resource(resource)
      %KillmailData{
        killmail_id: 12345,
        solar_system_id: 30000142,
        solar_system_name: "Jita",
        persisted: true
      }
  """
  @spec from_resource(struct()) :: t()
  def from_resource(resource) do
    %__MODULE__{
      # Core identification
      killmail_id: resource.killmail_id,
      zkb_hash: resource.zkb_hash,

      # Timestamps
      kill_time: resource.kill_time,
      processed_at: resource.inserted_at || DateTime.utc_now(),

      # System information
      solar_system_id: resource.solar_system_id,
      solar_system_name: resource.solar_system_name,
      region_id: resource.region_id,
      region_name: resource.region_name,
      solar_system_security: resource.solar_system_security,

      # Victim information
      victim_id: resource.victim_id,
      victim_name: resource.victim_name,
      victim_ship_id: resource.victim_ship_id,
      victim_ship_name: resource.victim_ship_name,
      victim_corporation_id: resource.victim_corporation_id,
      victim_corporation_name: resource.victim_corporation_name,

      # Attacker information
      attackers: resource.full_attacker_data,
      attacker_count: resource.attacker_count,
      final_blow_attacker_id: resource.final_blow_attacker_id,
      final_blow_attacker_name: resource.final_blow_attacker_name,
      final_blow_ship_id: resource.final_blow_ship_id,
      final_blow_ship_name: resource.final_blow_ship_name,

      # Economic data
      total_value: resource.total_value,
      points: resource.points,

      # Raw data
      # Not stored in database
      raw_zkb_data: nil,
      raw_esi_data: nil,

      # Status flags and metadata - keyword items at the end
      is_npc: resource.is_npc,
      is_solo: resource.is_solo,
      persisted: true,
      metadata: %{}
    }
  end

  # Extract helpers

  defp extract_killmail_id(zkb_data) do
    killmail_id =
      cond do
        is_map(zkb_data) && Map.has_key?(zkb_data, "killmail_id") ->
          zkb_data["killmail_id"]

        is_map(zkb_data) && Map.has_key?(zkb_data, :killmail_id) ->
          zkb_data.killmail_id

        is_map(zkb_data) && Map.has_key?(zkb_data, "zkb") && is_map(zkb_data["zkb"]) &&
            Map.has_key?(zkb_data["zkb"], "killmail_id") ->
          zkb_data["zkb"]["killmail_id"]

        true ->
          nil
      end

    if killmail_id, do: {:ok, killmail_id}, else: {:error, "Missing killmail_id"}
  end

  defp extract_zkb_hash(zkb_data) do
    zkb = extract_zkb_section(zkb_data)
    hash = Map.get(zkb, "hash")

    if hash, do: {:ok, hash}, else: {:error, "Missing zkb hash"}
  end

  defp extract_zkb_section(zkb_data) do
    cond do
      is_map(zkb_data) && Map.has_key?(zkb_data, "zkb") ->
        zkb_data["zkb"]

      is_map(zkb_data) && Map.has_key?(zkb_data, :zkb) ->
        zkb_data.zkb

      is_map(zkb_data) && (Map.has_key?(zkb_data, "totalValue") || Map.has_key?(zkb_data, "hash")) ->
        zkb_data

      true ->
        %{}
    end
  end

  defp extract_system_id(esi_data) do
    system_id = Map.get(esi_data, "solar_system_id")

    cond do
      is_integer(system_id) ->
        system_id

      is_binary(system_id) ->
        case Integer.parse(system_id) do
          {id, _} -> id
          :error -> nil
        end

      true ->
        nil
    end
  end

  defp extract_kill_time(esi_data) do
    kill_time = Map.get(esi_data, "killmail_time")

    cond do
      is_nil(kill_time) ->
        DateTime.utc_now()

      is_struct(kill_time, DateTime) ->
        kill_time

      is_binary(kill_time) ->
        case DateTime.from_iso8601(kill_time) do
          {:ok, datetime, _} -> datetime
          _ -> DateTime.utc_now()
        end

      true ->
        DateTime.utc_now()
    end
  end
end
