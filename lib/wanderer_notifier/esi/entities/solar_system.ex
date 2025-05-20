defmodule WandererNotifier.ESI.Entities.SolarSystem do
  @moduledoc """
  Domain model representing an EVE Online solar system from the ESI API.
  Provides a structured interface for working with solar system data.
  """

  @type t :: %__MODULE__{
          system_id: integer(),
          name: String.t(),
          constellation_id: integer(),
          constellation_name: String.t(),
          region_id: integer(),
          region_name: String.t(),
          star_id: integer(),
          planets: list(map()),
          security_status: float() | nil
        }

  defstruct [
    :system_id,
    :name,
    :constellation_id,
    :constellation_name,
    :region_id,
    :region_name,
    :star_id,
    :planets,
    :security_status
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
      ...>   "constellation_name" => "Test Constellation",
      ...>   "region_id" => 10000002,
      ...>   "region_name" => "Test Region",
      ...>   "star_id" => 40000001,
      ...>   "planets" => [%{"planet_id" => 50000001}]
      ...> })
      %WandererNotifier.ESI.Entities.SolarSystem{
        system_id: 30000142,
        name: "Jita",
        constellation_id: 20000020,
        constellation_name: "Test Constellation",
        region_id: 10000002,
        region_name: "Test Region",
        star_id: 40000001,
        planets: [%{"planet_id" => 50000001}]
      }
  """
  @spec from_esi_data(map()) :: t()
  def from_esi_data(data) when is_map(data) do
    %__MODULE__{
      system_id: data["system_id"],
      name: data["name"],
      constellation_id: data["constellation_id"],
      constellation_name: data["constellation_name"],
      region_id: data["region_id"],
      region_name: data["region_name"],
      star_id: data["star_id"],
      planets: data["planets"],
      security_status: data["security_status"]
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
    %{
      "system_id" => system.system_id,
      "name" => system.name,
      "constellation_id" => system.constellation_id,
      "constellation_name" => system.constellation_name,
      "region_id" => system.region_id,
      "region_name" => system.region_name,
      "star_id" => system.star_id,
      "planets" => system.planets,
      "security_status" => system.security_status
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
