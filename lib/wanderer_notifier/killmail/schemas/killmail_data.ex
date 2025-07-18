defmodule WandererNotifier.Killmail.Schemas.KillmailData do
  @moduledoc """
  Ecto embedded schema for complete killmail data.

  Represents the full structure of a killmail including victim, attackers,
  system information, and metadata. Supports both ESI and pre-enriched
  WebSocket data sources with comprehensive validation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WandererNotifier.Killmail.Schemas.{Victim, Attacker}

  @primary_key false
  embedded_schema do
    # Core identifiers
    field(:killmail_id, :integer)
    field(:killmail_time, :string)
    # zKillboard hash for ESI calls
    field(:hash, :string)

    # System information
    field(:solar_system_id, :integer)
    field(:solar_system_name, :string)
    field(:region_id, :integer)
    field(:region_name, :string)
    field(:constellation_id, :integer)
    field(:constellation_name, :string)
    field(:security_status, :float)

    # Value and metadata
    # ISK value
    field(:total_value, :decimal)
    # zKillboard points
    field(:points, :integer)
    field(:npc_kill, :boolean, default: false)
    field(:solo_kill, :boolean, default: false)
    field(:awox_kill, :boolean, default: false)

    # Embedded victim and attackers
    embeds_one(:victim, Victim)
    embeds_many(:attackers, Attacker)

    # Source tracking
    # "esi", "websocket", "zkillboard"
    field(:data_source, :string)
    field(:enriched, :boolean, default: false)
    field(:processed_at, :utc_datetime)

    # Raw data preservation for debugging/reprocessing
    field(:raw_zkb_data, :map)
    field(:raw_esi_data, :map)
    field(:raw_websocket_data, :map)

    timestamps()
  end

  @type t :: %__MODULE__{
          killmail_id: integer() | nil,
          killmail_time: String.t() | nil,
          hash: String.t() | nil,
          solar_system_id: integer() | nil,
          solar_system_name: String.t() | nil,
          region_id: integer() | nil,
          region_name: String.t() | nil,
          constellation_id: integer() | nil,
          constellation_name: String.t() | nil,
          security_status: float() | nil,
          total_value: Decimal.t() | nil,
          points: integer() | nil,
          npc_kill: boolean(),
          solo_kill: boolean(),
          awox_kill: boolean(),
          victim: Victim.t() | nil,
          attackers: [Attacker.t()],
          data_source: String.t() | nil,
          enriched: boolean(),
          processed_at: DateTime.t() | nil,
          raw_zkb_data: map() | nil,
          raw_esi_data: map() | nil,
          raw_websocket_data: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_data_sources ~w(esi websocket zkillboard)

  # Damage tolerance threshold for validating consistency between victim and attacker damage
  @damage_tolerance Application.compile_env(:wanderer_notifier, :damage_tolerance, 0.1)

  @doc """
  Creates a changeset for killmail data with comprehensive validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = killmail, attrs) do
    killmail
    |> cast(attrs, [
      :killmail_id,
      :killmail_time,
      :hash,
      :solar_system_id,
      :solar_system_name,
      :region_id,
      :region_name,
      :constellation_id,
      :constellation_name,
      :security_status,
      :total_value,
      :points,
      :npc_kill,
      :solo_kill,
      :awox_kill,
      :data_source,
      :enriched,
      :processed_at,
      :raw_zkb_data,
      :raw_esi_data,
      :raw_websocket_data
    ])
    |> cast_embed(:victim, required: true, with: &Victim.changeset/2)
    |> cast_embed(:attackers, required: true, with: &Attacker.changeset/2)
    |> validate_required([:killmail_id, :data_source])
    |> validate_inclusion(:data_source, @valid_data_sources)
    |> validate_killmail_id()
    |> validate_system_data()
    |> validate_time_format()
    |> validate_value_data()
    |> validate_attacker_consistency()
    |> validate_kill_metadata()
    |> set_processed_timestamp()
  end

  @doc """
  Creates a changeset from ESI killmail data.
  """
  @spec from_esi_data(map(), map()) :: Ecto.Changeset.t()
  def from_esi_data(esi_data, zkb_data \\ %{}) when is_map(esi_data) do
    attrs = %{
      killmail_id: esi_data["killmail_id"],
      killmail_time: esi_data["killmail_time"],
      hash: zkb_data["hash"],
      solar_system_id: esi_data["solar_system_id"],
      total_value: normalize_total_value(zkb_data["totalValue"]),
      points: zkb_data["points"],
      data_source: "esi",
      enriched: true,
      raw_esi_data: esi_data,
      raw_zkb_data: zkb_data,
      victim: esi_data["victim"] || %{},
      attackers: esi_data["attackers"] || []
    }

    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Creates a changeset from WebSocket enriched killmail data.
  """
  @spec from_websocket_data(map()) :: Ecto.Changeset.t()
  def from_websocket_data(ws_data) when is_map(ws_data) do
    attrs =
      build_websocket_attrs(ws_data)
      |> Map.put(:victim, ws_data["victim"] || %{})
      |> Map.put(:attackers, ws_data["attackers"] || [])

    %__MODULE__{}
    |> changeset(attrs)
  end

  defp normalize_total_value(nil), do: 0
  defp normalize_total_value(value) when is_number(value), do: value
  defp normalize_total_value(_), do: 0

  defp build_websocket_attrs(ws_data) do
    zkb_data = ws_data["zkb"] || %{}

    %{
      killmail_id: ws_data["killmail_id"],
      killmail_time: ws_data["killmail_time"],
      solar_system_id: ws_data["solar_system_id"],
      solar_system_name: ws_data["solar_system_name"],
      total_value: ws_data["total_value"] || zkb_data["totalValue"],
      points: ws_data["points"] || zkb_data["points"],
      data_source: "websocket",
      enriched: true,
      raw_websocket_data: ws_data
    }
  end

  @doc """
  Creates a changeset from zKillboard data (minimal, requires ESI enrichment).
  """
  @spec from_zkillboard_data(map()) :: Ecto.Changeset.t()
  def from_zkillboard_data(zkb_data) when is_map(zkb_data) do
    attrs = %{
      killmail_id: zkb_data["killmail_id"],
      hash: zkb_data["zkb"]["hash"],
      total_value: normalize_total_value(zkb_data["zkb"]["totalValue"]),
      points: zkb_data["zkb"]["points"],
      data_source: "zkillboard",
      enriched: false,
      raw_zkb_data: zkb_data
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Validates the complete killmail structure including relationships.
  """
  @spec validate_killmail_structure(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_killmail_structure(changeset) do
    changeset
    |> validate_victim_attacker_relationship()
    |> validate_final_blow_consistency()
    |> validate_damage_consistency()
  end

  @doc """
  Checks if the killmail represents a solo kill.
  """
  @spec is_solo_kill?(t()) :: boolean()
  def is_solo_kill?(%__MODULE__{attackers: attackers}) when is_list(attackers) do
    length(attackers) == 1
  end

  @doc """
  Checks if the killmail is an NPC kill.
  """
  @spec npc_kill?(t()) :: boolean()
  def npc_kill?(%__MODULE__{victim: %Victim{character_id: nil}}) do
    true
  end

  def npc_kill?(_), do: false

  @doc """
  Gets the final blow attacker.
  """
  @spec get_final_blow_attacker(t()) :: Attacker.t() | nil
  def get_final_blow_attacker(%__MODULE__{attackers: attackers}) do
    Attacker.get_final_blow_attacker(attackers)
  end

  @doc """
  Calculates total damage done by all attackers.
  """
  @spec total_damage_dealt(t()) :: integer()
  def total_damage_dealt(%__MODULE__{attackers: attackers}) do
    Attacker.total_damage(attackers)
  end

  @doc """
  Determines the security level category for the system.
  """
  @spec security_category(t()) ::
          :highsec | :lowsec | :nullsec | :wormhole | :thera | :pochven | :unknown
  def security_category(%__MODULE__{security_status: security}) when is_float(security) do
    cond do
      security >= 0.5 -> :highsec
      security > 0.0 -> :lowsec
      security <= 0.0 -> :nullsec
      true -> :unknown
    end
  end

  def security_category(%__MODULE__{solar_system_id: system_id}) when is_integer(system_id) do
    cond do
      # Thera - special wormhole system
      system_id == 31_000_005 -> :thera
      # Pochven systems (Triglavian space) - range 30045339-30045365
      system_id >= 30_045_339 and system_id <= 30_045_365 -> :pochven
      # Regular wormhole systems
      system_id >= 31_000_000 and system_id < 32_000_000 -> :wormhole
      # Unknown system
      true -> :unknown
    end
  end

  def security_category(_), do: :unknown

  # Private validation functions

  defp validate_killmail_id(changeset) do
    case get_field(changeset, :killmail_id) do
      nil ->
        add_error(changeset, :killmail_id, "Killmail ID is required")

      id when is_integer(id) ->
        if id > 0 and id <= 2_147_483_647 do
          changeset
        else
          add_error(changeset, :killmail_id, "Invalid killmail ID range")
        end

      _ ->
        add_error(changeset, :killmail_id, "Killmail ID must be an integer")
    end
  end

  defp validate_system_data(changeset) do
    changeset
    |> validate_solar_system_id()
    |> validate_security_status()
  end

  defp validate_solar_system_id(changeset) do
    case get_field(changeset, :solar_system_id) do
      # Optional for some data sources
      nil ->
        changeset

      system_id when is_integer(system_id) ->
        if system_id >= 30_000_000 and system_id <= 33_000_000 do
          changeset
        else
          add_error(changeset, :solar_system_id, "Invalid EVE solar system ID range")
        end

      _ ->
        add_error(changeset, :solar_system_id, "Solar system ID must be an integer")
    end
  end

  defp validate_security_status(changeset) do
    case get_field(changeset, :security_status) do
      nil ->
        changeset

      security when is_float(security) ->
        if security >= -1.0 and security <= 1.0 do
          changeset
        else
          add_error(changeset, :security_status, "Security status must be between -1.0 and 1.0")
        end

      _ ->
        add_error(changeset, :security_status, "Security status must be a float")
    end
  end

  defp validate_time_format(changeset) do
    case get_field(changeset, :killmail_time) do
      nil ->
        changeset

      time_str when is_binary(time_str) ->
        case DateTime.from_iso8601(time_str) do
          {:ok, _datetime, _offset} ->
            changeset

          {:error, _reason} ->
            add_error(changeset, :killmail_time, "Invalid ISO 8601 datetime format")
        end

      _ ->
        add_error(changeset, :killmail_time, "Killmail time must be a string")
    end
  end

  defp validate_value_data(changeset) do
    changeset
    |> validate_total_value()
    |> validate_points()
  end

  defp validate_total_value(changeset) do
    case get_field(changeset, :total_value) do
      nil ->
        changeset

      %Decimal{} = value ->
        if Decimal.compare(value, 0) != :lt do
          changeset
        else
          add_error(changeset, :total_value, "Total value must be non-negative")
        end

      value when is_number(value) ->
        if value >= 0 do
          changeset
        else
          add_error(changeset, :total_value, "Total value must be non-negative")
        end

      _ ->
        add_error(changeset, :total_value, "Total value must be a number")
    end
  end

  defp validate_points(changeset) do
    case get_field(changeset, :points) do
      nil ->
        changeset

      points when is_integer(points) ->
        if points >= 0 do
          changeset
        else
          add_error(changeset, :points, "Points must be non-negative")
        end

      _ ->
        add_error(changeset, :points, "Points must be an integer")
    end
  end

  defp validate_attacker_consistency(changeset) do
    case get_change(changeset, :attackers) do
      attackers when is_list(attackers) ->
        case Attacker.validate_attacker_list(attackers) do
          {:ok, _} -> changeset
          {:error, message} -> add_error(changeset, :attackers, message)
        end

      _ ->
        changeset
    end
  end

  defp validate_kill_metadata(changeset) do
    changeset
    |> derive_solo_kill()
    |> derive_npc_kill()
  end

  defp validate_victim_attacker_relationship(changeset) do
    victim = get_change(changeset, :victim)
    attackers = get_change(changeset, :attackers)

    case {victim, attackers} do
      {nil, _} ->
        add_error(changeset, :victim, "Victim is required")

      {_, []} ->
        add_error(changeset, :attackers, "At least one attacker is required")

      {%Victim{}, attackers} when is_list(attackers) ->
        # Additional relationship validations could go here
        changeset

      _ ->
        changeset
    end
  end

  defp validate_final_blow_consistency(changeset) do
    attackers = get_change(changeset, :attackers)

    if is_list(attackers) do
      validate_final_blow_count(changeset, attackers)
    else
      changeset
    end
  end

  defp validate_final_blow_count(changeset, attackers) do
    final_blow_count = count_final_blow_attackers(attackers)

    case final_blow_count do
      1 -> changeset
      0 -> add_error(changeset, :attackers, "Must have exactly one final blow attacker")
      _ -> add_error(changeset, :attackers, "Cannot have multiple final blow attackers")
    end
  end

  defp count_final_blow_attackers(attackers) do
    Enum.count(attackers, fn attacker ->
      case attacker do
        %Attacker{final_blow: final_blow} -> final_blow
        %Ecto.Changeset{} = cs -> Ecto.Changeset.get_field(cs, :final_blow)
        _ -> false
      end
    end)
  end

  defp validate_damage_consistency(changeset) do
    victim = get_change(changeset, :victim)
    attackers = get_change(changeset, :attackers)

    case {victim, attackers} do
      {victim_data, attackers} when is_list(attackers) ->
        victim_damage =
          case victim_data do
            %Victim{damage_taken: damage} -> damage
            %Ecto.Changeset{} = cs -> Ecto.Changeset.get_field(cs, :damage_taken)
            _ -> nil
          end

        total_attacker_damage = Attacker.total_damage(attackers)

        if (victim_damage && total_attacker_damage > 0) and
             abs(victim_damage - total_attacker_damage) > victim_damage * @damage_tolerance do
          add_error(
            changeset,
            :attackers,
            "Total attacker damage significantly differs from victim damage taken"
          )
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp derive_solo_kill(changeset) do
    case get_change(changeset, :attackers) do
      [_single_attacker] ->
        put_change(changeset, :solo_kill, true)

      attackers when is_list(attackers) and length(attackers) > 1 ->
        put_change(changeset, :solo_kill, false)

      _ ->
        changeset
    end
  end

  defp derive_npc_kill(changeset) do
    case get_change(changeset, :victim) do
      victim_data ->
        character_id =
          case victim_data do
            %Victim{character_id: id} -> id
            %Ecto.Changeset{} = cs -> Ecto.Changeset.get_field(cs, :character_id)
            _ -> nil
          end

        case character_id do
          nil -> put_change(changeset, :npc_kill, true)
          _id -> put_change(changeset, :npc_kill, false)
        end
    end
  end

  defp set_processed_timestamp(changeset) do
    put_change(changeset, :processed_at, DateTime.utc_now())
  end
end
