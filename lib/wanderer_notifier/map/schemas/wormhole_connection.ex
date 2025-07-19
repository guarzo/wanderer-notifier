defmodule WandererNotifier.Map.Schemas.WormholeConnection do
  @moduledoc """
  Ecto embedded schema for wormhole connection data.

  Represents static and dynamic wormhole connections between systems,
  including connection properties like mass limits, lifetime, and
  current status. Supports both K162 signatures and named statics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # Connection identification
    field(:connection_id, :string)
    # e.g., "ABC-123"
    field(:signature_id, :string)
    # "static", "wandering", "k162", "frigate"
    field(:connection_type, :string)

    # Wormhole type and properties
    # e.g., "C247", "K162", "N110"
    field(:wormhole_type, :string)
    # Human-readable name
    field(:wormhole_name, :string)
    # "small", "medium", "large", "xl"
    field(:size_class, :string)

    # Source and destination systems
    field(:source_system_id, :integer)
    field(:source_system_name, :string)
    field(:destination_system_id, :integer)
    field(:destination_system_name, :string)
    # "c1", "c2", "high", "low", "null", etc.
    field(:destination_class, :string)

    # Connection properties
    # Maximum single jump mass in kg
    field(:max_jump_mass, :integer)
    # Maximum total mass before collapse
    field(:max_total_mass, :integer)
    # Mass regeneration per hour
    field(:mass_regeneration, :integer)
    # Wormhole lifetime in hours
    field(:lifetime_hours, :integer)

    # Current status
    # "stable", "destab", "critical", "collapsed"
    field(:mass_status, :string)
    # "stable", "critical", "eol"
    field(:time_status, :string)
    # Current mass passed through
    field(:current_mass, :integer)
    field(:jumps_made, :integer, default: 0)

    # Discovery and tracking
    field(:discovered_at, :utc_datetime)
    # Character who discovered it
    field(:discovered_by, :string)
    field(:last_jump_at, :utc_datetime)
    # Estimated end of life
    field(:estimated_eol_at, :utc_datetime)
    field(:collapsed_at, :utc_datetime)

    # Map context
    field(:map_id, :string)
    field(:map_slug, :string)

    # Metadata
    field(:notes, :string)
    field(:locked, :boolean, default: false)
    field(:frigate_sized, :boolean, default: false)
    field(:is_k162, :boolean, default: false)

    timestamps()
  end

  @type t :: %__MODULE__{
          connection_id: String.t() | nil,
          signature_id: String.t() | nil,
          connection_type: String.t() | nil,
          wormhole_type: String.t() | nil,
          wormhole_name: String.t() | nil,
          size_class: String.t() | nil,
          source_system_id: integer() | nil,
          source_system_name: String.t() | nil,
          destination_system_id: integer() | nil,
          destination_system_name: String.t() | nil,
          destination_class: String.t() | nil,
          max_jump_mass: integer() | nil,
          max_total_mass: integer() | nil,
          mass_regeneration: integer() | nil,
          lifetime_hours: integer() | nil,
          mass_status: String.t() | nil,
          time_status: String.t() | nil,
          current_mass: integer() | nil,
          jumps_made: integer(),
          discovered_at: DateTime.t() | nil,
          discovered_by: String.t() | nil,
          last_jump_at: DateTime.t() | nil,
          estimated_eol_at: DateTime.t() | nil,
          collapsed_at: DateTime.t() | nil,
          map_id: String.t() | nil,
          map_slug: String.t() | nil,
          notes: String.t() | nil,
          locked: boolean(),
          frigate_sized: boolean(),
          is_k162: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_connection_types ~w(static wandering k162 frigate temporary)
  @valid_size_classes ~w(small medium large xl)
  @valid_mass_status ~w(stable destab critical collapsed)
  @valid_time_status ~w(stable critical eol)
  @valid_destination_classes ~w(c1 c2 c3 c4 c5 c6 high low null thera pochven unknown)

  # Common wormhole types and their properties
  @wormhole_properties %{
    # Class 1 Statics
    "C247" => %{
      size: "medium",
      max_jump: 20_000_000,
      max_total: 1_000_000_000,
      lifetime: 16,
      destination: "c3"
    },
    "J244" => %{
      size: "large",
      max_jump: 20_000_000,
      max_total: 1_000_000_000,
      lifetime: 16,
      destination: "low"
    },

    # Class 2 Statics
    "A239" => %{
      size: "medium",
      max_jump: 20_000_000,
      max_total: 1_000_000_000,
      lifetime: 16,
      destination: "c1"
    },
    "J449" => %{
      size: "large",
      max_jump: 20_000_000,
      max_total: 1_000_000_000,
      lifetime: 16,
      destination: "high"
    },

    # Class 3 Statics
    "D845" => %{
      size: "large",
      max_jump: 300_000_000,
      max_total: 2_000_000_000,
      lifetime: 16,
      destination: "c5"
    },
    "N968" => %{
      size: "large",
      max_jump: 300_000_000,
      max_total: 2_000_000_000,
      lifetime: 16,
      destination: "c3"
    },

    # K-Space connections
    "K162" => %{size: "variable", max_jump: 0, max_total: 0, lifetime: 16, destination: "unknown"},

    # Frigate holes
    "A009" => %{
      size: "small",
      max_jump: 5_000_000,
      max_total: 20_000_000,
      lifetime: 16,
      destination: "c13"
    }
  }

  @doc """
  Creates a changeset for wormhole connection data.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = connection, attrs) do
    connection
    |> cast(attrs, [
      :connection_id,
      :signature_id,
      :connection_type,
      :wormhole_type,
      :wormhole_name,
      :size_class,
      :source_system_id,
      :source_system_name,
      :destination_system_id,
      :destination_system_name,
      :destination_class,
      :max_jump_mass,
      :max_total_mass,
      :mass_regeneration,
      :lifetime_hours,
      :mass_status,
      :time_status,
      :current_mass,
      :jumps_made,
      :discovered_at,
      :discovered_by,
      :last_jump_at,
      :estimated_eol_at,
      :collapsed_at,
      :map_id,
      :map_slug,
      :notes,
      :locked,
      :frigate_sized,
      :is_k162
    ])
    |> validate_required([:wormhole_type, :connection_type])
    |> validate_connection_data()
    |> validate_system_data()
    |> validate_wormhole_properties()
    |> validate_mass_and_time_status()
    |> validate_timestamps()
    |> set_default_properties()
    |> set_discovery_timestamp()
  end

  @doc """
  Creates a changeset for a static wormhole connection.
  """
  @spec static_connection(String.t(), integer(), String.t(), map()) :: Ecto.Changeset.t()
  def static_connection(wormhole_type, source_system_id, source_system_name, attrs \\ %{}) do
    base_attrs = %{
      wormhole_type: wormhole_type,
      connection_type: "static",
      source_system_id: source_system_id,
      source_system_name: source_system_name,
      is_k162: false
    }

    attrs = Map.merge(base_attrs, attrs)
    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Creates a changeset for a K162 wormhole connection.
  """
  @spec k162_connection(integer(), String.t(), String.t(), map()) :: Ecto.Changeset.t()
  def k162_connection(source_system_id, source_system_name, signature_id, attrs \\ %{}) do
    base_attrs = %{
      wormhole_type: "K162",
      connection_type: "k162",
      signature_id: signature_id,
      source_system_id: source_system_id,
      source_system_name: source_system_name,
      is_k162: true
    }

    attrs = Map.merge(base_attrs, attrs)
    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Creates a changeset from static connection data.
  """
  @spec from_static_data(map(), integer(), String.t()) :: Ecto.Changeset.t()
  def from_static_data(static_data, system_id, system_name) when is_map(static_data) do
    destination = static_data["destination"] || %{}
    properties = static_data["properties"] || %{}

    attrs = %{
      wormhole_type: static_data["name"],
      wormhole_name: static_data["name"],
      connection_type: "static",
      source_system_id: system_id,
      source_system_name: system_name,
      destination_class: destination["short_name"] || destination["id"],
      max_jump_mass: properties["max_jump_mass"],
      max_total_mass: properties["max_mass"],
      mass_regeneration: properties["mass_regeneration"],
      lifetime_hours: parse_lifetime(properties["lifetime"]),
      mass_status: "stable",
      time_status: "stable"
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Updates connection status after a jump.
  """
  @spec record_jump(t(), integer()) :: Ecto.Changeset.t()
  def record_jump(%__MODULE__{} = connection, mass_used) do
    current_mass = (connection.current_mass || 0) + mass_used
    jumps_made = connection.jumps_made + 1

    attrs = %{
      current_mass: current_mass,
      jumps_made: jumps_made,
      last_jump_at: DateTime.utc_now(),
      mass_status: calculate_mass_status(current_mass, connection.max_total_mass)
    }

    changeset(connection, attrs)
  end

  @doc """
  Marks the connection as collapsed.
  """
  @spec collapse(t()) :: Ecto.Changeset.t()
  def collapse(%__MODULE__{} = connection) do
    attrs = %{
      mass_status: "collapsed",
      time_status: "eol",
      collapsed_at: DateTime.utc_now()
    }

    changeset(connection, attrs)
  end

  @doc """
  Updates the estimated end of life time.
  """
  @spec update_eol_estimate(t(), DateTime.t()) :: Ecto.Changeset.t()
  def update_eol_estimate(%__MODULE__{} = connection, eol_time) do
    time_status =
      if DateTime.diff(eol_time, DateTime.utc_now(), :hour) <= 4 do
        "critical"
      else
        "stable"
      end

    attrs = %{
      estimated_eol_at: eol_time,
      time_status: time_status
    }

    changeset(connection, attrs)
  end

  @doc """
  Checks if the connection is active (not collapsed).
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{mass_status: "collapsed"}), do: false
  def active?(%__MODULE__{collapsed_at: %DateTime{}}), do: false
  def active?(_), do: true

  @doc """
  Checks if the connection is end of life.
  """
  @spec end_of_life?(t()) :: boolean()
  def end_of_life?(%__MODULE__{time_status: "eol"}), do: true

  def end_of_life?(%__MODULE__{estimated_eol_at: %DateTime{} = eol}) do
    DateTime.compare(DateTime.utc_now(), eol) != :lt
  end

  def end_of_life?(_), do: false

  @doc """
  Checks if the connection is critically destabilized.
  """
  @spec critically_destabilized?(t()) :: boolean()
  def critically_destabilized?(%__MODULE__{mass_status: "critical"}), do: true
  def critically_destabilized?(_), do: false

  @doc """
  Gets the remaining lifetime in hours.
  """
  @spec remaining_lifetime_hours(t()) :: float() | nil
  def remaining_lifetime_hours(%__MODULE__{estimated_eol_at: nil}), do: nil

  def remaining_lifetime_hours(%__MODULE__{estimated_eol_at: eol}) do
    DateTime.diff(eol, DateTime.utc_now(), :second) / 3600
  end

  @doc """
  Gets the mass usage percentage.
  """
  @spec mass_usage_percentage(t()) :: float() | nil
  def mass_usage_percentage(%__MODULE__{current_mass: nil}), do: nil
  def mass_usage_percentage(%__MODULE__{max_total_mass: nil}), do: nil

  def mass_usage_percentage(%__MODULE__{current_mass: current, max_total_mass: max}) do
    current / max * 100
  end

  # Private validation functions

  defp validate_connection_data(changeset) do
    changeset
    |> validate_inclusion(:connection_type, @valid_connection_types)
    |> validate_inclusion(:size_class, @valid_size_classes)
    |> validate_wormhole_type_format()
    |> validate_signature_format()
  end

  defp validate_system_data(changeset) do
    changeset
    |> validate_system_id(:source_system_id)
    |> validate_system_id(:destination_system_id)
    |> validate_inclusion(:destination_class, @valid_destination_classes)
  end

  defp validate_wormhole_properties(changeset) do
    changeset
    |> validate_mass_properties()
    |> validate_lifetime()
    |> validate_frigate_hole_consistency()
  end

  defp validate_mass_and_time_status(changeset) do
    changeset
    |> validate_inclusion(:mass_status, @valid_mass_status)
    |> validate_inclusion(:time_status, @valid_time_status)
    |> validate_current_mass()
  end

  defp validate_timestamps(changeset) do
    changeset
    |> validate_discovery_time()
    |> validate_eol_time()
    |> validate_collapse_consistency()
  end

  defp validate_wormhole_type_format(changeset) do
    case get_field(changeset, :wormhole_type) do
      nil ->
        add_error(changeset, :wormhole_type, "Wormhole type is required")

      type when is_binary(type) ->
        if String.match?(type, ~r/^[A-Z]{1,2}[0-9]{3}$|^K162$|^EOL$/) do
          changeset
        else
          add_error(changeset, :wormhole_type, "Invalid wormhole type format")
        end

      _ ->
        add_error(changeset, :wormhole_type, "Wormhole type must be a string")
    end
  end

  defp validate_signature_format(changeset) do
    case get_field(changeset, :signature_id) do
      nil ->
        changeset

      sig when is_binary(sig) ->
        if String.match?(sig, ~r/^[A-Z]{3}-[0-9]{3}$/) do
          changeset
        else
          add_error(changeset, :signature_id, "Invalid signature format (expected ABC-123)")
        end

      _ ->
        add_error(changeset, :signature_id, "Signature ID must be a string")
    end
  end

  defp validate_system_id(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      system_id when is_integer(system_id) ->
        if system_id >= 30_000_000 and system_id <= 33_000_000 do
          changeset
        else
          add_error(changeset, field, "Invalid EVE solar system ID range")
        end

      _ ->
        add_error(changeset, field, "System ID must be an integer")
    end
  end

  defp validate_mass_properties(changeset) do
    changeset
    |> validate_number(:max_jump_mass, greater_than: 0)
    |> validate_number(:max_total_mass, greater_than: 0)
    |> validate_number(:mass_regeneration, greater_than_or_equal_to: 0)
    |> validate_mass_consistency()
  end

  defp validate_mass_consistency(changeset) do
    max_jump = get_field(changeset, :max_jump_mass)
    max_total = get_field(changeset, :max_total_mass)

    case {max_jump, max_total} do
      {jump, total} when is_integer(jump) and is_integer(total) ->
        if jump <= total do
          changeset
        else
          add_error(changeset, :max_jump_mass, "Cannot exceed max total mass")
        end

      _ ->
        changeset
    end
  end

  defp validate_current_mass(changeset) do
    current = get_field(changeset, :current_mass)
    max_total = get_field(changeset, :max_total_mass)

    case {current, max_total} do
      {nil, _} ->
        changeset

      {curr, nil} when is_integer(curr) ->
        changeset

      {curr, max} when is_integer(curr) and is_integer(max) ->
        if curr <= max do
          changeset
        else
          add_error(changeset, :current_mass, "Cannot exceed max total mass")
        end

      _ ->
        changeset
    end
  end

  defp validate_lifetime(changeset) do
    changeset
    |> validate_number(:lifetime_hours, greater_than: 0, less_than_or_equal_to: 48)
  end

  defp validate_frigate_hole_consistency(changeset) do
    frigate_sized = get_field(changeset, :frigate_sized)
    max_jump = get_field(changeset, :max_jump_mass)

    case {frigate_sized, max_jump} do
      {true, mass} when is_integer(mass) and mass > 10_000_000 ->
        add_error(changeset, :frigate_sized, "Frigate holes cannot have jump mass > 10M kg")

      _ ->
        changeset
    end
  end

  defp validate_discovery_time(changeset) do
    discovered = get_field(changeset, :discovered_at)

    case discovered do
      nil ->
        changeset

      time when is_struct(time, DateTime) ->
        if DateTime.compare(time, DateTime.utc_now()) == :gt do
          add_error(changeset, :discovered_at, "Cannot be in the future")
        else
          changeset
        end

      _ ->
        add_error(changeset, :discovered_at, "Must be a valid DateTime")
    end
  end

  defp validate_eol_time(changeset) do
    eol = get_field(changeset, :estimated_eol_at)
    discovered = get_field(changeset, :discovered_at)

    case {eol, discovered} do
      {nil, _} ->
        changeset

      {eol_time, nil} when is_struct(eol_time, DateTime) ->
        changeset

      {eol_time, disc_time}
      when is_struct(eol_time, DateTime) and is_struct(disc_time, DateTime) ->
        if DateTime.compare(eol_time, disc_time) == :gt do
          changeset
        else
          add_error(changeset, :estimated_eol_at, "Must be after discovery time")
        end

      _ ->
        changeset
    end
  end

  defp validate_collapse_consistency(changeset) do
    collapsed_at = get_field(changeset, :collapsed_at)
    mass_status = get_field(changeset, :mass_status)

    case {collapsed_at, mass_status} do
      {nil, "collapsed"} ->
        add_error(changeset, :collapsed_at, "Required when mass status is collapsed")

      {%DateTime{}, status} when status != "collapsed" ->
        add_error(changeset, :mass_status, "Must be collapsed when collapse time is set")

      _ ->
        changeset
    end
  end

  defp set_default_properties(changeset) do
    wormhole_type = get_field(changeset, :wormhole_type)

    case Map.get(@wormhole_properties, wormhole_type) do
      nil ->
        changeset

      properties ->
        changeset
        |> put_change_if_nil(:max_jump_mass, properties.max_jump)
        |> put_change_if_nil(:max_total_mass, properties.max_total)
        |> put_change_if_nil(:lifetime_hours, properties.lifetime)
        |> put_change_if_nil(:size_class, properties.size)
        |> put_change_if_nil(:destination_class, properties.destination)
    end
  end

  defp set_discovery_timestamp(changeset) do
    case get_field(changeset, :discovered_at) do
      nil -> put_change(changeset, :discovered_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  # Helper functions

  defp parse_lifetime(lifetime) when is_binary(lifetime) do
    case Integer.parse(lifetime) do
      {hours, ""} -> hours
      _ -> nil
    end
  end

  defp parse_lifetime(lifetime) when is_integer(lifetime), do: lifetime
  defp parse_lifetime(_), do: nil

  defp calculate_mass_status(current_mass, max_mass)
       when is_integer(current_mass) and is_integer(max_mass) do
    percentage = current_mass / max_mass * 100

    cond do
      percentage >= 95 -> "critical"
      percentage >= 50 -> "destab"
      true -> "stable"
    end
  end

  defp calculate_mass_status(_, _), do: "stable"

  defp put_change_if_nil(changeset, field, value) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, value)
      _ -> changeset
    end
  end
end
