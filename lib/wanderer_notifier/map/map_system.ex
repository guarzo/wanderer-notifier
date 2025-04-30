defmodule WandererNotifier.Map.MapSystem do
  @moduledoc """
  Struct for representing a system in the map context.
  """

  @enforce_keys [:solar_system_id, :name]
  defstruct [
    :solar_system_id,
    :name,
    :original_name,
    :system_type,
    :type_description,
    :class_title,
    :effect_name,
    :is_shattered,
    :locked,
    :region_name,
    :static_details,
    :sun_type_id,
    :id
  ]

  @type t :: %__MODULE__{
          solar_system_id: String.t() | integer(),
          name: String.t(),
          original_name: String.t() | nil,
          system_type: String.t() | atom() | nil,
          type_description: String.t() | nil,
          class_title: String.t() | nil,
          effect_name: String.t() | nil,
          is_shattered: boolean() | nil,
          locked: boolean() | nil,
          region_name: String.t() | nil,
          static_details: list() | nil,
          sun_type_id: integer() | nil,
          id: String.t() | integer() | nil
        }

  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  def is_wormhole?(%__MODULE__{system_type: type}) do
    type in [:wormhole, "wormhole", "Wormhole"]
  end

  def format_display_name(%__MODULE__{name: name, class_title: class, effect_name: effect}) do
    [name, class, effect]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Updates a MapSystem struct with static info from a map.
  """
  def update_with_static_info(system, static_info) do
    struct(__MODULE__, Map.merge(Map.from_struct(system), static_info))
  end
end
