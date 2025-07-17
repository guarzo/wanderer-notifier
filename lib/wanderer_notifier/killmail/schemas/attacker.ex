defmodule WandererNotifier.Killmail.Schemas.Attacker do
  @moduledoc """
  Ecto embedded schema for killmail attacker data.

  Represents an attacker in a killmail with character, corporation,
  alliance, ship, and weapon information. Includes final blow tracking
  and damage attribution.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias WandererNotifier.Killmail.Schemas.SharedValidations

  @primary_key false
  embedded_schema do
    field(:character_id, :integer)
    field(:character_name, :string)
    field(:corporation_id, :integer)
    field(:corporation_name, :string)
    field(:corporation_ticker, :string)
    field(:alliance_id, :integer)
    field(:alliance_name, :string)
    field(:alliance_ticker, :string)
    field(:ship_type_id, :integer)
    field(:ship_name, :string)
    field(:weapon_type_id, :integer)
    field(:weapon_name, :string)
    field(:damage_done, :integer)
    field(:final_blow, :boolean, default: false)
    field(:security_status, :float)

    # Additional EVE Online fields
    field(:faction_id, :integer)
    field(:faction_name, :string)

    timestamps()
  end

  @type t :: %__MODULE__{
          character_id: integer() | nil,
          character_name: String.t() | nil,
          corporation_id: integer() | nil,
          corporation_name: String.t() | nil,
          corporation_ticker: String.t() | nil,
          alliance_id: integer() | nil,
          alliance_name: String.t() | nil,
          alliance_ticker: String.t() | nil,
          ship_type_id: integer() | nil,
          ship_name: String.t() | nil,
          weapon_type_id: integer() | nil,
          weapon_name: String.t() | nil,
          damage_done: integer() | nil,
          final_blow: boolean(),
          security_status: float() | nil,
          faction_id: integer() | nil,
          faction_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a changeset for attacker data with comprehensive validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = attacker, attrs) do
    attacker
    |> cast(attrs, [
      :character_id,
      :character_name,
      :corporation_id,
      :corporation_name,
      :corporation_ticker,
      :alliance_id,
      :alliance_name,
      :alliance_ticker,
      :ship_type_id,
      :ship_name,
      :weapon_type_id,
      :weapon_name,
      :damage_done,
      :final_blow,
      :security_status,
      :faction_id,
      :faction_name
    ])
    |> validate_required([:damage_done, :final_blow])
    |> validate_character_data()
    |> validate_corporation_data()
    |> validate_ship_data()
    |> validate_weapon_data()
    |> validate_damage_and_final_blow()
    |> validate_security_status()
  end

  @doc """
  Creates a changeset from raw ESI attacker data.
  """
  @spec from_esi_data(map()) :: Ecto.Changeset.t()
  def from_esi_data(esi_attacker) when is_map(esi_attacker) do
    changeset(%__MODULE__{}, esi_attacker)
  end

  @doc """
  Creates a changeset from WebSocket enriched attacker data.
  """
  @spec from_websocket_data(map()) :: Ecto.Changeset.t()
  def from_websocket_data(ws_attacker) when is_map(ws_attacker) do
    normalized = normalize_websocket_fields(ws_attacker)
    changeset(%__MODULE__{}, normalized)
  end

  @doc """
  Validates attacker list to ensure exactly one final blow attacker.
  """
  @spec validate_attacker_list([t()]) :: {:ok, [t()]} | {:error, String.t()}
  def validate_attacker_list(attackers) when is_list(attackers) do
    final_blow_count =
      attackers
      |> Enum.count(fn attacker ->
        case attacker do
          %__MODULE__{final_blow: final_blow} -> final_blow
          %Ecto.Changeset{} -> Ecto.Changeset.get_field(attacker, :final_blow)
          _ -> false
        end
      end)

    case final_blow_count do
      1 -> {:ok, attackers}
      0 -> {:error, "Attacker list must have exactly one final blow attacker"}
      n when n > 1 -> {:error, "Attacker list cannot have multiple final blow attackers"}
    end
  end

  @doc """
  Returns the final blow attacker from a list of attackers.
  """
  @spec get_final_blow_attacker([t()]) :: t() | nil
  def get_final_blow_attacker(attackers) when is_list(attackers) do
    Enum.find(attackers, fn attacker ->
      case attacker do
        %__MODULE__{final_blow: final_blow} -> final_blow
        %Ecto.Changeset{} -> Ecto.Changeset.get_field(attacker, :final_blow)
        _ -> false
      end
    end)
  end

  @doc """
  Calculates total damage done by all attackers.
  """
  @spec total_damage([t()]) :: integer()
  def total_damage(attackers) when is_list(attackers) do
    attackers
    |> Enum.map(&(&1.damage_done || 0))
    |> Enum.sum()
  end

  # Private validation functions

  defp validate_character_data(changeset) do
    changeset
    |> validate_character_id_format()
    |> validate_character_name_consistency()
  end

  defp validate_corporation_data(changeset) do
    changeset
    |> validate_corporation_id_format()
    |> validate_corporation_name_consistency()
    |> validate_ticker_format()
  end

  defp validate_ship_data(changeset) do
    changeset
    |> validate_ship_type_id_format()
    |> validate_ship_name_consistency()
  end

  defp validate_weapon_data(changeset) do
    changeset
    |> validate_weapon_type_id_format()
    |> validate_weapon_name_consistency()
  end

  defp validate_damage_and_final_blow(changeset) do
    changeset
    |> validate_damage_done()
    |> validate_final_blow_logic()
  end

  defp validate_security_status(changeset) do
    changeset
    |> validate_number(:security_status, greater_than_or_equal_to: -10.0)
    |> validate_number(:security_status, less_than_or_equal_to: 5.0)
  end

  defp validate_character_id_format(changeset) do
    case get_field(changeset, :character_id) do
      # NPC attackers don't have character IDs
      nil ->
        changeset

      character_id when is_integer(character_id) ->
        if character_id >= 90_000_000 and character_id <= 100_000_000_000 do
          changeset
        else
          add_error(changeset, :character_id, "Invalid EVE character ID range")
        end

      _ ->
        add_error(changeset, :character_id, "Character ID must be an integer")
    end
  end

  defp validate_character_name_consistency(changeset) do
    SharedValidations.validate_character_name_consistency(
      changeset,
      :character_id,
      :character_name
    )
  end

  defp validate_corporation_id_format(changeset) do
    case get_field(changeset, :corporation_id) do
      nil ->
        changeset

      corp_id when is_integer(corp_id) ->
        if corp_id >= 1_000_000 and corp_id <= 2_147_483_647 do
          changeset
        else
          add_error(changeset, :corporation_id, "Invalid EVE corporation ID range")
        end

      _ ->
        add_error(changeset, :corporation_id, "Corporation ID must be an integer")
    end
  end

  defp validate_corporation_name_consistency(changeset) do
    SharedValidations.validate_corporation_name_consistency(
      changeset,
      :corporation_id,
      :corporation_name
    )
  end

  defp validate_ticker_format(changeset) do
    case get_field(changeset, :corporation_ticker) do
      nil ->
        changeset

      ticker when is_binary(ticker) ->
        if Regex.match?(~r/^[A-Z0-9\-\.]{1,5}$/, ticker) do
          changeset
        else
          add_error(changeset, :corporation_ticker, "Invalid ticker format (1-5 chars, A-Z0-9.-)")
        end

      _ ->
        add_error(changeset, :corporation_ticker, "Ticker must be a string")
    end
  end

  defp validate_ship_type_id_format(changeset) do
    case get_field(changeset, :ship_type_id) do
      # Some attackers might not have ships (structures?)
      nil ->
        changeset

      ship_id when is_integer(ship_id) ->
        if ship_id >= 1 and ship_id <= 100_000_000 do
          changeset
        else
          add_error(changeset, :ship_type_id, "Invalid EVE ship type ID range")
        end

      _ ->
        add_error(changeset, :ship_type_id, "Ship type ID must be an integer")
    end
  end

  defp validate_ship_name_consistency(changeset) do
    ship_type_id = get_field(changeset, :ship_type_id)
    ship_name = get_field(changeset, :ship_name)

    case {ship_type_id, ship_name} do
      # Valid for some attacker types
      {nil, nil} ->
        changeset

      {id, nil} when not is_nil(id) ->
        add_error(changeset, :ship_name, "Ship name required when ship type ID is present")

      {nil, name} when not is_nil(name) ->
        add_error(changeset, :ship_type_id, "Ship type ID required when ship name is present")

      _ ->
        changeset
    end
  end

  defp validate_weapon_type_id_format(changeset) do
    case get_field(changeset, :weapon_type_id) do
      # Weapon can be unknown
      nil ->
        changeset

      weapon_id when is_integer(weapon_id) ->
        if weapon_id >= 1 and weapon_id <= 100_000_000 do
          changeset
        else
          add_error(changeset, :weapon_type_id, "Invalid EVE weapon type ID range")
        end

      _ ->
        add_error(changeset, :weapon_type_id, "Weapon type ID must be an integer")
    end
  end

  defp validate_weapon_name_consistency(changeset) do
    weapon_type_id = get_field(changeset, :weapon_type_id)
    weapon_name = get_field(changeset, :weapon_name)

    case {weapon_type_id, weapon_name} do
      {nil, nil} ->
        changeset

      {id, nil} when not is_nil(id) ->
        add_error(changeset, :weapon_name, "Weapon name required when weapon type ID is present")

      {nil, name} when not is_nil(name) ->
        add_error(
          changeset,
          :weapon_type_id,
          "Weapon type ID required when weapon name is present"
        )

      _ ->
        changeset
    end
  end

  defp validate_damage_done(changeset) do
    changeset
    |> validate_number(:damage_done, greater_than_or_equal_to: 0)
    # Max 32-bit integer
    |> validate_number(:damage_done, less_than: 2_147_483_647)
  end

  defp validate_final_blow_logic(changeset) do
    damage_done = get_field(changeset, :damage_done)
    final_blow = get_field(changeset, :final_blow)

    case {damage_done, final_blow} do
      {0, true} ->
        if allowed_zero_damage?(changeset) do
          changeset
        else
          add_error(changeset, :final_blow, "Final blow attacker must have damage > 0")
        end

      _ ->
        changeset
    end
  end

  # Helper function to check if zero damage is allowed for this attacker
  defp allowed_zero_damage?(changeset) do
    weapon_type_id = get_field(changeset, :weapon_type_id)
    character_id = get_field(changeset, :character_id)

    # Allow zero damage for:
    # 1. Smartbomb modules (weapon type IDs in smartbomb range)
    # 2. NPC final blows (character_id is nil)
    is_smartbomb_weapon?(weapon_type_id) or is_npc_attacker?(character_id)
  end

  # Check if weapon is a smartbomb (approximate range, may need refinement)
  defp is_smartbomb_weapon?(weapon_type_id) when is_integer(weapon_type_id) do
    # Smartbomb weapon type IDs are typically in the range 9000-10000
    # This is an approximation and may need adjustment based on actual EVE data
    weapon_type_id >= 9000 and weapon_type_id <= 10000
  end

  defp is_smartbomb_weapon?(_), do: false

  # Check if attacker is an NPC (no character_id)
  defp is_npc_attacker?(character_id), do: is_nil(character_id)

  defp normalize_websocket_fields(ws_data) when is_map(ws_data) do
    # Use shared function for common fields, add attacker-specific fields
    additional_fields = [
      "weapon_type_id",
      "weapon_name",
      "damage_done",
      "security_status"
    ]

    normalized =
      SharedValidations.normalize_websocket_character_data(ws_data, additional_fields)
      |> Map.put_new(:final_blow, ws_data["final_blow"] || false)

    # Use shared validation to normalize field types
    field_mappings = [
      {:character_id, :integer},
      {:corporation_id, :integer},
      {:alliance_id, :integer},
      {:ship_type_id, :integer},
      {:weapon_type_id, :integer},
      {:damage_done, :integer}
    ]

    changeset = %__MODULE__{} |> Ecto.Changeset.change(normalized)
    changeset = SharedValidations.normalize_websocket_fields(changeset, field_mappings)
    changeset.changes
  end
end
