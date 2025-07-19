defmodule WandererNotifier.Map.Schemas.CharacterLocation do
  @moduledoc """
  Ecto embedded schema for character location and tracking data.

  Represents a character's location in space with tracking metadata,
  supporting both real-time updates from SSE events and cached tracking state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # Character identification
    field(:character_id, :string)
    field(:character_eve_id, :string)
    field(:name, :string)

    # Corporation and alliance data
    field(:corporation_id, :integer)
    field(:corporation_name, :string)
    field(:corporation_ticker, :string)
    field(:alliance_id, :integer)
    field(:alliance_name, :string)
    field(:alliance_ticker, :string)

    # Location and ship data
    field(:solar_system_id, :integer)
    field(:solar_system_name, :string)
    field(:ship_type_id, :integer)
    field(:ship_name, :string)

    # Status and tracking
    field(:online, :boolean, default: false)
    field(:tracked, :boolean, default: false)
    field(:last_seen_at, :utc_datetime)
    field(:tracking_enabled_at, :utc_datetime)
    field(:tracking_disabled_at, :utc_datetime)

    # Map context
    field(:map_id, :string)
    field(:map_slug, :string)

    # Event metadata
    field(:last_event_id, :string)
    field(:last_event_type, :string)
    # "sse", "api", "manual"
    field(:last_update_source, :string)

    timestamps()
  end

  @type t :: %__MODULE__{
          character_id: String.t() | nil,
          character_eve_id: String.t() | nil,
          name: String.t() | nil,
          corporation_id: integer() | nil,
          corporation_name: String.t() | nil,
          corporation_ticker: String.t() | nil,
          alliance_id: integer() | nil,
          alliance_name: String.t() | nil,
          alliance_ticker: String.t() | nil,
          solar_system_id: integer() | nil,
          solar_system_name: String.t() | nil,
          ship_type_id: integer() | nil,
          ship_name: String.t() | nil,
          online: boolean(),
          tracked: boolean(),
          last_seen_at: DateTime.t() | nil,
          tracking_enabled_at: DateTime.t() | nil,
          tracking_disabled_at: DateTime.t() | nil,
          map_id: String.t() | nil,
          map_slug: String.t() | nil,
          last_event_id: String.t() | nil,
          last_event_type: String.t() | nil,
          last_update_source: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_update_sources ~w(sse api manual)
  @valid_event_types ~w(character_added character_removed character_updated system_change)

  @doc """
  Creates a changeset for character location data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = character_location, attrs) do
    character_location
    |> cast(attrs, [
      :character_id,
      :character_eve_id,
      :name,
      :corporation_id,
      :corporation_name,
      :corporation_ticker,
      :alliance_id,
      :alliance_name,
      :alliance_ticker,
      :solar_system_id,
      :solar_system_name,
      :ship_type_id,
      :ship_name,
      :online,
      :tracked,
      :last_seen_at,
      :tracking_enabled_at,
      :tracking_disabled_at,
      :map_id,
      :map_slug,
      :last_event_id,
      :last_event_type,
      :last_update_source
    ])
    |> validate_required([:character_id, :name])
    |> validate_character_data()
    |> validate_corporation_data()
    |> validate_location_data()
    |> validate_tracking_data()
    |> validate_event_metadata()
    |> set_last_seen_timestamp()
  end

  @doc """
  Creates a changeset from SSE character event data.
  """
  @spec from_sse_event(map(), String.t()) :: Ecto.Changeset.t()
  def from_sse_event(event_data, event_type) when is_map(event_data) do
    payload = event_data["payload"] || event_data

    attrs = %{
      character_id: payload["character_id"] || payload["id"],
      character_eve_id: payload["character_eve_id"],
      name: payload["name"],
      corporation_id: payload["corporation_id"],
      alliance_id: payload["alliance_id"],
      ship_type_id: payload["ship_type_id"],
      online: payload["online"],
      last_event_id: event_data["id"],
      last_event_type: event_type,
      last_update_source: "sse",
      map_id: event_data["map_id"]
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Creates a changeset from existing MapCharacter struct.
  """
  @spec from_map_character(WandererNotifier.Domains.CharacterTracking.Character.t()) ::
          Ecto.Changeset.t()
  def from_map_character(map_character) do
    attrs = %{
      character_id: to_string(map_character.character_id),
      character_eve_id: to_string(map_character.eve_id),
      name: map_character.name,
      corporation_id: map_character.corporation_id,
      corporation_ticker: map_character.corporation_ticker,
      alliance_id: map_character.alliance_id,
      alliance_ticker: map_character.alliance_ticker,
      tracked: map_character.tracked,
      last_update_source: "api"
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Updates tracking status for a character.
  """
  @spec set_tracking_status(t(), boolean()) :: Ecto.Changeset.t()
  def set_tracking_status(%__MODULE__{} = character_location, tracked) do
    now = DateTime.utc_now()

    attrs = %{
      tracked: tracked,
      tracking_enabled_at: if(tracked, do: now, else: nil),
      tracking_disabled_at: if(tracked, do: nil, else: now)
    }

    changeset(character_location, attrs)
  end

  @doc """
  Updates character location from system change.
  """
  @spec update_location(t(), integer(), String.t() | nil) :: Ecto.Changeset.t()
  def update_location(%__MODULE__{} = character_location, system_id, system_name \\ nil) do
    attrs = %{
      solar_system_id: system_id,
      solar_system_name: system_name,
      last_event_type: "system_change",
      last_update_source: "sse"
    }

    changeset(character_location, attrs)
  end

  @doc """
  Checks if character is currently being tracked.
  """
  @spec tracked?(t()) :: boolean()
  def tracked?(%__MODULE__{tracked: tracked}), do: tracked

  @doc """
  Checks if character is currently online.
  """
  @spec online?(t()) :: boolean()
  def online?(%__MODULE__{online: online}), do: online

  @doc """
  Gets the last activity timestamp for the character.
  """
  @spec last_activity(t()) :: DateTime.t() | nil
  def last_activity(%__MODULE__{last_seen_at: last_seen}), do: last_seen

  @doc """
  Calculates how long ago the character was last seen.
  """
  @spec time_since_last_seen(t()) :: integer() | nil
  def time_since_last_seen(%__MODULE__{last_seen_at: nil}), do: nil

  def time_since_last_seen(%__MODULE__{last_seen_at: last_seen}) do
    DateTime.diff(DateTime.utc_now(), last_seen, :second)
  end

  # Private validation functions

  defp validate_character_data(changeset) do
    changeset
    |> validate_length(:character_id, min: 1, max: 100)
    |> validate_length(:name, min: 1, max: 37)
    |> validate_character_eve_id()
  end

  defp validate_character_eve_id(changeset) do
    case get_field(changeset, :character_eve_id) do
      nil ->
        changeset

      eve_id when is_binary(eve_id) ->
        # EVE character IDs are typically numeric strings
        case Integer.parse(eve_id) do
          {id, ""} when id >= 90_000_000 and id <= 100_000_000_000 ->
            changeset

          _ ->
            add_error(changeset, :character_eve_id, "Invalid EVE character ID format or range")
        end

      _ ->
        add_error(changeset, :character_eve_id, "Character EVE ID must be a string")
    end
  end

  defp validate_corporation_data(changeset) do
    changeset
    |> validate_corporation_id()
    |> validate_ticker_format(:corporation_ticker)
    |> validate_ticker_format(:alliance_ticker)
  end

  defp validate_corporation_id(changeset) do
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

  defp validate_ticker_format(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      ticker when is_binary(ticker) ->
        if Regex.match?(~r/^[A-Z0-9\-\.]{1,5}$/, ticker) do
          changeset
        else
          add_error(changeset, field, "Invalid ticker format (1-5 chars, A-Z0-9.-)")
        end

      _ ->
        add_error(changeset, field, "Ticker must be a string")
    end
  end

  defp validate_location_data(changeset) do
    changeset
    |> validate_solar_system_id()
    |> validate_ship_type_id()
  end

  defp validate_solar_system_id(changeset) do
    case get_field(changeset, :solar_system_id) do
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

  defp validate_ship_type_id(changeset) do
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

  defp validate_tracking_data(changeset) do
    changeset
    |> validate_tracking_timestamps()
  end

  defp validate_tracking_timestamps(changeset) do
    tracked = get_field(changeset, :tracked)
    enabled_at = get_field(changeset, :tracking_enabled_at)
    disabled_at = get_field(changeset, :tracking_disabled_at)

    case {tracked, enabled_at, disabled_at} do
      {true, nil, _} ->
        add_error(changeset, :tracking_enabled_at, "Required when tracked is true")

      {false, _, nil} ->
        add_error(changeset, :tracking_disabled_at, "Required when tracked is false")

      {true, %DateTime{} = enabled, %DateTime{} = disabled} ->
        if DateTime.compare(enabled, disabled) == :gt do
          changeset
        else
          add_error(changeset, :tracking_enabled_at, "Must be after tracking_disabled_at")
        end

      _ ->
        changeset
    end
  end

  defp validate_event_metadata(changeset) do
    changeset
    |> validate_inclusion(:last_update_source, @valid_update_sources)
    |> validate_inclusion(:last_event_type, @valid_event_types)
    |> validate_map_identifiers()
  end

  defp validate_map_identifiers(changeset) do
    map_id = get_field(changeset, :map_id)
    map_slug = get_field(changeset, :map_slug)

    case {map_id, map_slug} do
      # Both optional
      {nil, nil} ->
        changeset

      {id, nil} when is_binary(id) ->
        # Validate UUID format for map_id
        if String.match?(id, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i) do
          changeset
        else
          add_error(changeset, :map_id, "Invalid UUID format")
        end

      {nil, slug} when is_binary(slug) ->
        if String.length(slug) > 0 and String.length(slug) <= 50 do
          changeset
        else
          add_error(changeset, :map_slug, "Map slug must be 1-50 characters")
        end

      # Both present is okay
      {_id, _slug} ->
        changeset
    end
  end

  defp set_last_seen_timestamp(changeset) do
    case get_field(changeset, :last_seen_at) do
      nil -> put_change(changeset, :last_seen_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
