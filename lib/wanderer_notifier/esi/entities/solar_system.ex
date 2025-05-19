defmodule WandererNotifier.ESI.Entities.SolarSystem do
  @moduledoc """
  Domain model representing an EVE Online solar system from the ESI API.
  Provides a structured interface for working with solar system data.
  """

  @type t :: %__MODULE__{
          system_id: integer(),
          name: String.t(),
          constellation_id: integer(),
          security_status: float(),
          security_class: String.t() | nil,
          position: %{x: float(), y: float(), z: float()} | nil,
          star_id: integer() | nil,
          planets: list(map()) | nil,
          region_id: integer() | nil
        }

  defstruct [
    :system_id,
    :name,
    :constellation_id,
    :security_status,
    :security_class,
    :position,
    :star_id,
    :planets,
    :region_id
  ]

  @doc """
  Creates a new SolarSystem struct from raw ESI API data.

  ## Parameters
    - data: The raw solar system data from ESI API

  ## Example
      iex> WandererNotifier.ESI.Entities.SolarSystem.from_esi_data(%{
      ...>   "system_id" => 30000142,
      ...>   "name" => "Jita",
      ...>   "constellation_id" => 20000020,
      ...>   "security_status" => 0.9,
      ...>   "security_class" => "B",
      ...>   "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
      ...>   "star_id" => 40000001,
      ...>   "planets" => [%{"planet_id" => 50000001}],
      ...>   "region_id" => 10000002
      ...> })
      %WandererNotifier.ESI.Entities.SolarSystem{
        system_id: 30000142,
        name: "Jita",
        constellation_id: 20000020,
        security_status: 0.9,
        security_class: "B",
        position: %{x: 1.0, y: 2.0, z: 3.0},
        star_id: 40000001,
        planets: [%{"planet_id" => 50000001}],
        region_id: 10000002
      }
  """
  @spec from_esi_data(map()) :: t()
  def from_esi_data(data) when is_map(data) do
    position =
      if Map.has_key?(data, "position") do
        pos = Map.get(data, "position")

        %{
          x: Map.get(pos, "x", 0.0),
          y: Map.get(pos, "y", 0.0),
          z: Map.get(pos, "z", 0.0)
        }
      else
        nil
      end

    %__MODULE__{
      system_id: Map.get(data, "system_id"),
      name: Map.get(data, "name"),
      constellation_id: Map.get(data, "constellation_id"),
      security_status: Map.get(data, "security_status"),
      security_class: Map.get(data, "security_class"),
      position: position,
      star_id: Map.get(data, "star_id"),
      planets: Map.get(data, "planets"),
      region_id: Map.get(data, "region_id")
    }
  end

  @doc """
  Converts a SolarSystem struct to a map suitable for storage or serialization.

  ## Parameters
    - system: The SolarSystem struct to convert

  ## Returns
    A map with string keys containing the solar system data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = system) do
    position =
      if system.position do
        %{
          "x" => system.position.x,
          "y" => system.position.y,
          "z" => system.position.z
        }
      else
        nil
      end

    %{
      "system_id" => system.system_id,
      "name" => system.name,
      "constellation_id" => system.constellation_id,
      "security_status" => system.security_status,
      "security_class" => system.security_class,
      "position" => position,
      "star_id" => system.star_id,
      "planets" => system.planets,
      "region_id" => system.region_id
    }
  end

  @doc """
  Calculates the simplified security status band for a solar system.

  ## Parameters
    - system: The SolarSystem struct or a security status value

  ## Returns
    A string representing the security band (e.g., "High", "Low", "Null")
  """
  @spec security_band(t() | float()) :: String.t()
  def security_band(%__MODULE__{security_status: sec_status}) do
    security_band(sec_status)
  end

  def security_band(sec_status) when is_number(sec_status) and sec_status >= 0.5, do: "High"
  def security_band(sec_status) when is_number(sec_status) and sec_status > 0.0, do: "Low"
  def security_band(sec_status) when is_number(sec_status), do: "Null"
  def security_band(_), do: "Unknown"
end
