defmodule WandererNotifier.Map.Schemas.SystemActivity do
  @moduledoc """
  Ecto embedded schema for system activity tracking.

  Represents activities within a solar system including character presence,
  ship movements, and system state changes. Supports tracking both
  K-Space and W-Space (wormhole) systems with their unique characteristics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # System identification
    field(:solar_system_id, :integer)
    field(:solar_system_name, :string)
    field(:original_name, :string)
    field(:temporary_name, :string)

    # System classification
    # "k_space", "w_space", "thera", "pochven"
    field(:system_type, :string)
    # "c1", "c2", "c3", "c4", "c5", "c6", "high", "low", "null"
    field(:system_class, :string)
    field(:security_status, :float)
    field(:class_title, :string)
    field(:type_description, :string)

    # Wormhole-specific data
    # "magnetar", "pulsar", "red_giant", etc.
    field(:effect_name, :string)
    # 1-6 for effect strength
    field(:effect_power, :integer)
    field(:is_shattered, :boolean, default: false)
    field(:sun_type_id, :integer)

    # Location hierarchy
    field(:region_id, :integer)
    field(:region_name, :string)
    field(:constellation_id, :integer)
    field(:constellation_name, :string)

    # Triglavian invasion status
    # "normal", "invaded", "edencom"
    field(:triglavian_invasion_status, :string)

    # System state
    field(:locked, :boolean, default: false)
    field(:tracked, :boolean, default: false)

    # Activity metrics
    field(:character_count, :integer, default: 0)
    field(:active_character_count, :integer, default: 0)
    field(:last_activity_at, :utc_datetime)
    field(:first_seen_at, :utc_datetime)

    # Static wormhole connections (for W-Space)
    field(:static_connections, {:array, :map}, default: [])
    field(:static_names, {:array, :string}, default: [])
    field(:wandering_connections, {:array, :string}, default: [])

    # Map context
    field(:map_id, :string)
    field(:map_slug, :string)

    # Event tracking
    field(:last_event_id, :string)
    field(:last_event_type, :string)
    field(:last_update_source, :string)

    timestamps()
  end

  @type t :: %__MODULE__{
          solar_system_id: integer() | nil,
          solar_system_name: String.t() | nil,
          original_name: String.t() | nil,
          temporary_name: String.t() | nil,
          system_type: String.t() | nil,
          system_class: String.t() | nil,
          security_status: float() | nil,
          class_title: String.t() | nil,
          type_description: String.t() | nil,
          effect_name: String.t() | nil,
          effect_power: integer() | nil,
          is_shattered: boolean(),
          sun_type_id: integer() | nil,
          region_id: integer() | nil,
          region_name: String.t() | nil,
          constellation_id: integer() | nil,
          constellation_name: String.t() | nil,
          triglavian_invasion_status: String.t() | nil,
          locked: boolean(),
          tracked: boolean(),
          character_count: integer(),
          active_character_count: integer(),
          last_activity_at: DateTime.t() | nil,
          first_seen_at: DateTime.t() | nil,
          static_connections: [map()],
          static_names: [String.t()],
          wandering_connections: [String.t()],
          map_id: String.t() | nil,
          map_slug: String.t() | nil,
          last_event_id: String.t() | nil,
          last_event_type: String.t() | nil,
          last_update_source: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_system_types ~w(k_space w_space thera pochven abyssal unknown)
  @valid_system_classes ~w(c1 c2 c3 c4 c5 c6 high low null thera pochven abyssal unknown)
  @valid_wh_effects ~w(magnetar pulsar red_giant cataclysmic_variable wolf_rayet black_hole)
  @valid_invasion_status ~w(normal invaded edencom fortress)
  @valid_event_types ~w(add_system deleted_system system_metadata_changed character_enter character_exit)
  @valid_update_sources ~w(sse api manual)

  @doc """
  Creates a changeset for system activity data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = system_activity, attrs) do
    system_activity
    |> cast(attrs, [
      :solar_system_id,
      :solar_system_name,
      :original_name,
      :temporary_name,
      :system_type,
      :system_class,
      :security_status,
      :class_title,
      :type_description,
      :effect_name,
      :effect_power,
      :is_shattered,
      :sun_type_id,
      :region_id,
      :region_name,
      :constellation_id,
      :constellation_name,
      :triglavian_invasion_status,
      :locked,
      :tracked,
      :character_count,
      :active_character_count,
      :last_activity_at,
      :first_seen_at,
      :static_connections,
      :static_names,
      :wandering_connections,
      :map_id,
      :map_slug,
      :last_event_id,
      :last_event_type,
      :last_update_source
    ])
    |> validate_required([:solar_system_id])
    |> validate_system_identification()
    |> validate_system_classification()
    |> validate_wormhole_data()
    |> validate_activity_metrics()
    |> validate_static_connections()
    |> validate_event_metadata()
    |> set_first_seen_timestamp()
  end

  @doc """
  Creates a changeset from SSE system event data.
  """
  @spec from_sse_event(map(), String.t()) :: Ecto.Changeset.t()
  def from_sse_event(event_data, event_type) when is_map(event_data) do
    payload = event_data["payload"] || event_data

    attrs = %{
      solar_system_id: payload["solar_system_id"] || payload["id"],
      solar_system_name: payload["name"] || payload["solar_system_name"],
      original_name: payload["original_name"],
      temporary_name: payload["temporary_name"],
      system_type: payload["system_type"],
      system_class: payload["system_class"],
      security_status: payload["security_status"],
      locked: payload["locked"],
      last_event_id: event_data["id"],
      last_event_type: event_type,
      last_update_source: "sse",
      map_id: event_data["map_id"]
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Creates a changeset from existing MapSystem struct.
  """
  @spec from_map_system(WandererNotifier.Domains.Tracking.Entities.System.t()) :: Ecto.Changeset.t()
  def from_map_system(map_system) do
    attrs = %{
      solar_system_id: parse_system_id(map_system.solar_system_id),
      solar_system_name: map_system.name,
      original_name: map_system.original_name,
      temporary_name: map_system.temporary_name,
      system_type: to_string(map_system.system_type),
      system_class: to_string(map_system.system_class),
      security_status: map_system.security_status,
      class_title: map_system.class_title,
      type_description: map_system.type_description,
      effect_name: map_system.effect_name,
      effect_power: map_system.effect_power,
      is_shattered: map_system.is_shattered,
      sun_type_id: map_system.sun_type_id,
      region_id: map_system.region_id,
      region_name: map_system.region_name,
      constellation_id: map_system.constellation_id,
      constellation_name: map_system.constellation_name,
      triglavian_invasion_status: map_system.triglavian_invasion_status,
      locked: map_system.locked,
      static_connections: map_system.static_details || [],
      static_names: map_system.statics || [],
      last_update_source: "api"
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Updates character activity metrics for the system.
  """
  @spec update_character_activity(t(), integer(), integer()) :: Ecto.Changeset.t()
  def update_character_activity(%__MODULE__{} = system_activity, total_chars, active_chars) do
    attrs = %{
      character_count: total_chars,
      active_character_count: active_chars,
      last_activity_at: DateTime.utc_now()
    }

    changeset(system_activity, attrs)
  end

  @doc """
  Marks the system as tracked or untracked.
  """
  @spec set_tracking_status(t(), boolean()) :: Ecto.Changeset.t()
  def set_tracking_status(%__MODULE__{} = system_activity, tracked) do
    changeset(system_activity, %{tracked: tracked})
  end

  @doc """
  Checks if the system is a wormhole system.
  """
  @spec wormhole_system?(t()) :: boolean()
  def wormhole_system?(%__MODULE__{system_type: "w_space"}), do: true

  def wormhole_system?(%__MODULE__{solar_system_id: system_id}) when is_integer(system_id) do
    system_id >= 31_000_000 and system_id < 32_000_000
  end

  def wormhole_system?(_), do: false

  @doc """
  Checks if the system is K-Space (known space).
  """
  @spec kspace_system?(t()) :: boolean()
  def kspace_system?(%__MODULE__{system_type: "k_space"}), do: true
  def kspace_system?(system_activity), do: not wormhole_system?(system_activity)

  @doc """
  Gets the security level category.
  """
  @spec security_category(t()) ::
          :highsec | :lowsec | :nullsec | :wormhole | :thera | :pochven | :unknown
  def security_category(%__MODULE__{system_type: "w_space"}), do: :wormhole
  def security_category(%__MODULE__{system_type: "thera"}), do: :thera
  def security_category(%__MODULE__{system_type: "pochven"}), do: :pochven

  def security_category(%__MODULE__{security_status: security}) when is_float(security) do
    cond do
      security >= 0.5 -> :highsec
      security > 0.0 -> :lowsec
      security <= 0.0 -> :nullsec
      true -> :unknown
    end
  end

  def security_category(_), do: :unknown

  @doc """
  Checks if the system has current activity.
  """
  @spec has_activity?(t()) :: boolean()
  def has_activity?(%__MODULE__{character_count: count}) when is_integer(count) and count > 0,
    do: true

  def has_activity?(_), do: false

  @doc """
  Gets time since last activity in seconds.
  """
  @spec time_since_last_activity(t()) :: integer() | nil
  def time_since_last_activity(%__MODULE__{last_activity_at: nil}), do: nil

  def time_since_last_activity(%__MODULE__{last_activity_at: last_activity}) do
    DateTime.diff(DateTime.utc_now(), last_activity, :second)
  end

  # Private validation functions

  defp validate_system_identification(changeset) do
    changeset
    |> validate_solar_system_id()
    |> validate_system_names()
  end

  defp validate_solar_system_id(changeset) do
    case get_field(changeset, :solar_system_id) do
      nil ->
        add_error(changeset, :solar_system_id, "Solar system ID is required")

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

  defp validate_system_names(changeset) do
    changeset
    |> validate_length(:solar_system_name, max: 100)
    |> validate_length(:original_name, max: 100)
    |> validate_length(:temporary_name, max: 100)
  end

  defp validate_system_classification(changeset) do
    changeset
    |> validate_inclusion(:system_type, @valid_system_types)
    |> validate_inclusion(:system_class, @valid_system_classes)
    |> validate_inclusion(:triglavian_invasion_status, @valid_invasion_status)
    |> validate_security_status()
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

  defp validate_wormhole_data(changeset) do
    changeset
    |> validate_wormhole_effect()
    |> validate_effect_power()
    |> validate_shattered_status()
  end

  defp validate_wormhole_effect(changeset) do
    case get_field(changeset, :effect_name) do
      nil ->
        changeset

      effect when is_binary(effect) ->
        if effect in @valid_wh_effects do
          changeset
        else
          add_error(changeset, :effect_name, "Invalid wormhole effect")
        end

      _ ->
        add_error(changeset, :effect_name, "Effect name must be a string")
    end
  end

  defp validate_effect_power(changeset) do
    case get_field(changeset, :effect_power) do
      nil ->
        changeset

      power when is_integer(power) ->
        if power >= 1 and power <= 6 do
          changeset
        else
          add_error(changeset, :effect_power, "Effect power must be between 1 and 6")
        end

      _ ->
        add_error(changeset, :effect_power, "Effect power must be an integer")
    end
  end

  defp validate_shattered_status(changeset) do
    system_type = get_field(changeset, :system_type)
    is_shattered = get_field(changeset, :is_shattered)

    case {system_type, is_shattered} do
      # Valid shattered wormhole
      {"w_space", true} ->
        changeset

      # Valid normal wormhole
      {"w_space", false} ->
        changeset

      {_, true} ->
        add_error(changeset, :is_shattered, "Only wormhole systems can be shattered")

      _ ->
        changeset
    end
  end

  defp validate_activity_metrics(changeset) do
    changeset
    |> validate_number(:character_count, greater_than_or_equal_to: 0)
    |> validate_number(:active_character_count, greater_than_or_equal_to: 0)
    |> validate_character_count_consistency()
  end

  defp validate_character_count_consistency(changeset) do
    total_count = get_field(changeset, :character_count)
    active_count = get_field(changeset, :active_character_count)

    case {total_count, active_count} do
      {total, active} when is_integer(total) and is_integer(active) ->
        if active <= total do
          changeset
        else
          add_error(changeset, :active_character_count, "Cannot exceed total character count")
        end

      _ ->
        changeset
    end
  end

  defp validate_static_connections(changeset) do
    changeset
    |> validate_static_connection_format()
    |> validate_static_names_format()
  end

  defp validate_static_connection_format(changeset) do
    case get_field(changeset, :static_connections) do
      nil ->
        changeset

      [] ->
        changeset

      connections when is_list(connections) ->
        if Enum.all?(connections, &valid_static_connection?/1) do
          changeset
        else
          add_error(changeset, :static_connections, "Invalid static connection format")
        end

      _ ->
        add_error(changeset, :static_connections, "Static connections must be a list")
    end
  end

  defp validate_static_names_format(changeset) do
    case get_field(changeset, :static_names) do
      nil ->
        changeset

      [] ->
        changeset

      names when is_list(names) ->
        if Enum.all?(names, &is_binary/1) do
          changeset
        else
          add_error(changeset, :static_names, "All static names must be strings")
        end

      _ ->
        add_error(changeset, :static_names, "Static names must be a list")
    end
  end

  defp validate_event_metadata(changeset) do
    changeset
    |> validate_inclusion(:last_event_type, @valid_event_types)
    |> validate_inclusion(:last_update_source, @valid_update_sources)
  end

  defp set_first_seen_timestamp(changeset) do
    case get_field(changeset, :first_seen_at) do
      nil -> put_change(changeset, :first_seen_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  # Helper functions

  defp parse_system_id(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_system_id(system_id) when is_integer(system_id), do: system_id
  defp parse_system_id(_), do: nil

  defp valid_static_connection?(connection) when is_map(connection) do
    required_keys = ["name", "destination", "properties"]
    Enum.all?(required_keys, &Map.has_key?(connection, &1))
  end

  defp valid_static_connection?(_), do: false
end
