defmodule WandererNotifier.Killmail.Schemas.Victim do
  @moduledoc """
  Ecto embedded schema for killmail victim data.

  Represents the victim of a killmail with character, corporation,
  alliance, and ship information. Supports both ESI-enriched and
  pre-enriched data from different sources.
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
    field(:damage_taken, :integer)
    field(:position, :map)

    # Additional fields for EVE Online game data
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
          damage_taken: integer() | nil,
          position: map() | nil,
          faction_id: integer() | nil,
          faction_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a changeset for victim data with comprehensive validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = victim, attrs) do
    victim
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
      :damage_taken,
      :position,
      :faction_id,
      :faction_name
    ])
    |> validate_required([:damage_taken])
    |> validate_character_data()
    |> validate_corporation_data()
    |> validate_ship_data()
    |> validate_damage_taken()
  end

  @doc """
  Creates a changeset from raw killmail data (ESI format).
  """
  @spec from_esi_data(map()) :: Ecto.Changeset.t()
  def from_esi_data(esi_victim) when is_map(esi_victim) do
    changeset(%__MODULE__{}, esi_victim)
  end

  @doc """
  Creates a changeset from WebSocket enriched data.
  """
  @spec from_websocket_data(map()) :: Ecto.Changeset.t()
  def from_websocket_data(ws_victim) when is_map(ws_victim) do
    # WebSocket data might have slightly different field names
    normalized = normalize_websocket_fields(ws_victim)
    changeset(%__MODULE__{}, normalized)
  end

  @doc """
  Validates that the victim data represents a valid EVE Online entity.
  """
  @spec validate_victim(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_victim(changeset) do
    changeset
    |> validate_eve_entity_ids()
    |> validate_damage_consistency()
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
    |> validate_ship_name_presence()
  end

  defp validate_damage_taken(changeset) do
    changeset
    |> validate_number(:damage_taken, greater_than: 0)
    # Max 32-bit integer
    |> validate_number(:damage_taken, less_than: 2_147_483_647)
  end

  defp validate_character_id_format(changeset) do
    case get_field(changeset, :character_id) do
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

  defp validate_ship_name_presence(changeset) do
    ship_type_id = get_field(changeset, :ship_type_id)
    ship_name = get_field(changeset, :ship_name)

    case {ship_type_id, ship_name} do
      {id, nil} when not is_nil(id) ->
        add_error(changeset, :ship_name, "Ship name required when ship type ID is present")

      {nil, name} when not is_nil(name) ->
        add_error(changeset, :ship_type_id, "Ship type ID required when ship name is present")

      _ ->
        changeset
    end
  end

  defp validate_eve_entity_ids(changeset) do
    # Cross-validate that entity relationships make sense
    changeset
    |> validate_alliance_corporation_relationship()
  end

  defp validate_alliance_corporation_relationship(changeset) do
    alliance_id = get_field(changeset, :alliance_id)
    corp_id = get_field(changeset, :corporation_id)

    case {alliance_id, corp_id} do
      # No alliance is valid
      {nil, _} ->
        changeset

      {alliance_id, nil} when not is_nil(alliance_id) ->
        add_error(changeset, :corporation_id, "Corporation required when alliance is present")

      _ ->
        changeset
    end
  end

  defp validate_damage_consistency(changeset) do
    # Ensure damage_taken is reasonable for the context
    damage = get_field(changeset, :damage_taken)

    # Increased threshold to accommodate capital ship damage
    # Titans and other capital ships can take significantly more damage
    if damage && damage > 10_000_000_000 do
      add_error(changeset, :damage_taken, "Damage taken seems unreasonably high")
    else
      changeset
    end
  end

  defp normalize_websocket_fields(ws_data) when is_map(ws_data) do
    # Use shared function for common fields, add victim-specific fields
    additional_fields = ["damage_taken"]

    normalized = SharedValidations.normalize_websocket_character_data(ws_data, additional_fields)

    # Use shared validation to normalize field types
    field_mappings = [
      {:character_id, :integer},
      {:corporation_id, :integer},
      {:alliance_id, :integer},
      {:ship_type_id, :integer},
      {:damage_taken, :integer}
    ]

    changeset = %__MODULE__{} |> Ecto.Changeset.change(normalized)
    changeset = SharedValidations.normalize_websocket_fields(changeset, field_mappings)
    changeset.changes
  end
end
