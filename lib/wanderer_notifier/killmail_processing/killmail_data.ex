defmodule WandererNotifier.KillmailProcessing.KillmailData do
  @moduledoc """
  Defines the in-memory structure for killmail data during processing.

  This struct provides a standardized representation of killmail data as it moves
  through various processing stages, regardless of its source. It ensures all
  components in the pipeline have a consistent view of the data.

  ## Structure Fields

  - `killmail_id`: Unique identifier for the killmail
  - `zkb_data`: Raw data from zKillboard API
  - `esi_data`: Data from EVE Swagger Interface (ESI) API
  - `solar_system_id`: ID of the solar system where the kill occurred
  - `solar_system_name`: Name of the solar system where the kill occurred
  - `kill_time`: UTC DateTime when the kill occurred
  - `victim`: Map containing victim details (character, ship, etc.)
  - `attackers`: List of maps with attacker details
  - `persisted`: Flag indicating if the killmail has been saved to database
  - `metadata`: Arbitrary metadata for tracking processing state

  ## Usage

  ```elixir
  # Create from zkb and esi data
  killmail = KillmailData.from_zkb_and_esi(zkb_data, esi_data)

  # Create from a database resource
  killmail = KillmailData.from_resource(resource)
  ```

  This structure is designed to work seamlessly with the Extractor module for
  consistent data access throughout the processing pipeline.
  """

  @type t :: %__MODULE__{
          killmail_id: integer(),
          zkb_data: map(),
          esi_data: map(),
          solar_system_id: integer() | nil,
          solar_system_name: String.t() | nil,
          kill_time: DateTime.t() | nil,
          victim: map() | nil,
          attackers: list() | nil,
          persisted: boolean(),
          metadata: map()
        }

  defstruct [
    :killmail_id,
    :zkb_data,
    :esi_data,
    :solar_system_id,
    :solar_system_name,
    :kill_time,
    :victim,
    :attackers,
    persisted: false,
    metadata: %{}
  ]

  @doc """
  Creates a KillmailData struct from zKillboard data and ESI API data.

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
        zkb_data: ^zkb_data,
        esi_data: ^esi_data,
        solar_system_id: 30000142,
        solar_system_name: "Jita"
      }
  """
  @spec from_zkb_and_esi(map(), map()) :: t()
  def from_zkb_and_esi(zkb_data, esi_data) do
    # Extract killmail_id from zkb_data
    killmail_id = extract_killmail_id(zkb_data)

    # Extract system information
    system_id = extract_system_id(esi_data)
    system_name = Map.get(esi_data, "solar_system_name")

    # Extract timestamp
    kill_time = extract_kill_time(esi_data)

    # Extract victim and attackers
    victim = Map.get(esi_data, "victim")
    attackers = Map.get(esi_data, "attackers")

    # Create the struct
    %__MODULE__{
      killmail_id: killmail_id,
      zkb_data: zkb_data,
      esi_data: esi_data,
      solar_system_id: system_id,
      solar_system_name: system_name,
      kill_time: kill_time,
      victim: victim,
      attackers: attackers,
      persisted: false,
      metadata: %{}
    }
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
      killmail_id: resource.killmail_id,
      solar_system_id: resource.solar_system_id,
      solar_system_name: resource.solar_system_name,
      kill_time: resource.kill_time,
      victim: resource.full_victim_data,
      attackers: resource.full_attacker_data,
      # Mark as persisted since it came from the database
      persisted: true,
      metadata: %{}
    }
  end

  # Private helper functions

  # Extract killmail_id from zkb_data with support for both string and atom keys
  defp extract_killmail_id(%{"killmail_id" => id}) when not is_nil(id), do: id
  defp extract_killmail_id(%{killmail_id: id}) when not is_nil(id), do: id

  defp extract_killmail_id(%{"zkb" => %{"killmail_id" => id}}) when not is_nil(id), do: id
  defp extract_killmail_id(%{zkb: %{"killmail_id" => id}}) when not is_nil(id), do: id
  defp extract_killmail_id(%{"zkb" => %{killmail_id: id}}) when not is_nil(id), do: id
  defp extract_killmail_id(%{zkb: %{killmail_id: id}}) when not is_nil(id), do: id

  defp extract_killmail_id(_), do: nil

  # Extract system_id from esi_data with type conversion
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

  # Extract kill_time from esi_data with format conversion
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
