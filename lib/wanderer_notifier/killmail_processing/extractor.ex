defmodule WandererNotifier.KillmailProcessing.Extractor do
  @moduledoc """
  Functions for extracting data from killmail structures.

  This module provides a consistent interface for extracting data from different
  killmail data formats:

  - KillmailData struct: The in-memory killmail representation during processing
  - KillmailResource: The database entity from Ash Resources
  - Raw maps: Data from external APIs like zKillboard and ESI

  ## Usage

  ```elixir
  # Get killmail ID consistently from any format
  id = Extractor.get_killmail_id(killmail)

  # Extract solar system information
  system_id = Extractor.get_system_id(killmail)
  system_name = Extractor.get_system_name(killmail)

  # Get victim and attacker information
  victim = Extractor.get_victim(killmail)
  attackers = Extractor.get_attackers(killmail)

  # Get debug information for logging
  debug_data = Extractor.debug_data(killmail)
  ```

  The module uses pattern matching to handle various formats, ensuring data access
  is consistent throughout the codebase regardless of the source.
  """

  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  @type killmail_source :: KillmailData.t() | KillmailResource.t() | map()

  @doc """
  Gets the killmail ID from various killmail data formats.

  ## Examples

      iex> get_killmail_id(%KillmailData{killmail_id: 12345})
      12345

      iex> get_killmail_id(%{"killmail_id" => 12345})
      12345

      iex> get_killmail_id(%{killmail_id: 12345})
      12345
  """
  @spec get_killmail_id(killmail_source()) :: integer() | nil
  def get_killmail_id(%KillmailData{killmail_id: id}) when not is_nil(id), do: id
  def get_killmail_id(%KillmailResource{killmail_id: id}) when not is_nil(id), do: id
  def get_killmail_id(%{killmail_id: id}) when not is_nil(id), do: id
  def get_killmail_id(%{"killmail_id" => id}) when not is_nil(id), do: id
  def get_killmail_id(%{"zkb" => %{"killmail_id" => id}}) when not is_nil(id), do: id
  def get_killmail_id(_), do: nil

  @doc """
  Gets the solar system ID from various killmail data formats.

  ## Examples

      iex> get_system_id(%KillmailData{solar_system_id: 30000142})
      30000142

      iex> get_system_id(%{esi_data: %{"solar_system_id" => 30000142}})
      30000142
  """
  @spec get_system_id(killmail_source()) :: integer() | nil
  def get_system_id(%KillmailData{solar_system_id: id}) when not is_nil(id), do: id
  def get_system_id(%KillmailResource{solar_system_id: id}) when not is_nil(id), do: id
  def get_system_id(%{esi_data: %{"solar_system_id" => id}}) when not is_nil(id), do: id
  def get_system_id(%{solar_system_id: id}) when not is_nil(id), do: id
  def get_system_id(%{"solar_system_id" => id}) when not is_nil(id), do: id
  def get_system_id(_), do: nil

  @doc """
  Gets the solar system name from various killmail data formats.

  ## Examples

      iex> get_system_name(%KillmailData{solar_system_name: "Jita"})
      "Jita"

      iex> get_system_name(%{esi_data: %{"solar_system_name" => "Jita"}})
      "Jita"
  """
  @spec get_system_name(killmail_source()) :: String.t() | nil
  def get_system_name(%KillmailData{solar_system_name: name}) when not is_nil(name), do: name
  def get_system_name(%KillmailResource{solar_system_name: name}) when not is_nil(name), do: name
  def get_system_name(%{esi_data: %{"solar_system_name" => name}}) when not is_nil(name), do: name
  def get_system_name(%{solar_system_name: name}) when not is_nil(name), do: name
  def get_system_name(%{"solar_system_name" => name}) when not is_nil(name), do: name
  def get_system_name(_), do: nil

  @doc """
  Gets the victim data from various killmail data formats.

  ## Examples

      iex> get_victim(%KillmailData{victim: %{"character_id" => 12345}})
      %{"character_id" => 12345}

      iex> get_victim(%{esi_data: %{"victim" => %{"character_id" => 12345}}})
      %{"character_id" => 12345}
  """
  @spec get_victim(killmail_source()) :: map()
  def get_victim(%KillmailData{victim: victim}) when not is_nil(victim), do: victim
  def get_victim(%KillmailResource{full_victim_data: victim}) when not is_nil(victim), do: victim
  def get_victim(%{esi_data: %{"victim" => victim}}) when not is_nil(victim), do: victim
  def get_victim(%{victim: victim}) when not is_nil(victim), do: victim
  def get_victim(%{"victim" => victim}) when not is_nil(victim), do: victim
  def get_victim(_), do: %{}

  @doc """
  Gets the victim character ID from the killmail.

  ## Examples

      iex> get_victim_character_id(%KillmailData{victim: %{"character_id" => 12345}})
      12345

      iex> get_victim_character_id(%{esi_data: %{"victim" => %{"character_id" => 12345}}})
      12345
  """
  @spec get_victim_character_id(killmail_source()) :: integer() | nil
  def get_victim_character_id(killmail) do
    victim = get_victim(killmail)
    victim_id = Map.get(victim, "character_id")

    if is_binary(victim_id) do
      case Integer.parse(victim_id) do
        {id, _} -> id
        _ -> nil
      end
    else
      victim_id
    end
  end

  @doc """
  Gets the victim character name from the killmail.

  ## Examples

      iex> get_victim_character_name(%KillmailData{victim: %{"character_name" => "John Doe"}})
      "John Doe"

      iex> get_victim_character_name(%{esi_data: %{"victim" => %{"character_name" => "John Doe"}}})
      "John Doe"
  """
  @spec get_victim_character_name(killmail_source()) :: String.t() | nil
  def get_victim_character_name(killmail) do
    victim = get_victim(killmail)
    Map.get(victim, "character_name")
  end

  @doc """
  Gets the victim ship type ID from the killmail.

  ## Examples

      iex> get_victim_ship_type_id(%KillmailData{victim: %{"ship_type_id" => 12345}})
      12345

      iex> get_victim_ship_type_id(%{esi_data: %{"victim" => %{"ship_type_id" => 12345}}})
      12345
  """
  @spec get_victim_ship_type_id(killmail_source()) :: integer() | nil
  def get_victim_ship_type_id(killmail) do
    victim = get_victim(killmail)
    Map.get(victim, "ship_type_id")
  end

  @doc """
  Gets the victim ship type name from the killmail.

  ## Examples

      iex> get_victim_ship_type_name(%KillmailData{victim: %{"ship_type_name" => "Retriever"}})
      "Retriever"

      iex> get_victim_ship_type_name(%{esi_data: %{"victim" => %{"ship_type_name" => "Retriever"}}})
      "Retriever"
  """
  @spec get_victim_ship_type_name(killmail_source()) :: String.t() | nil
  def get_victim_ship_type_name(killmail) do
    victim = get_victim(killmail)
    Map.get(victim, "ship_type_name")
  end

  @doc """
  Gets the attackers data from various killmail data formats.

  ## Examples

      iex> get_attackers(%KillmailData{attackers: [%{"character_id" => 12345}]})
      [%{"character_id" => 12345}]

      iex> get_attackers(%{esi_data: %{"attackers" => [%{"character_id" => 12345}]}})
      [%{"character_id" => 12345}]
  """
  @spec get_attackers(killmail_source()) :: list(map())
  def get_attackers(%KillmailData{attackers: attackers}) when not is_nil(attackers), do: attackers

  def get_attackers(%KillmailResource{full_attacker_data: attackers}) when not is_nil(attackers),
    do: attackers

  def get_attackers(%{esi_data: %{"attackers" => attackers}}) when not is_nil(attackers),
    do: attackers

  def get_attackers(%{attackers: attackers}) when not is_nil(attackers), do: attackers
  def get_attackers(%{"attackers" => attackers}) when not is_nil(attackers), do: attackers
  def get_attackers(_), do: []

  @doc """
  Gets the kill time from various killmail data formats.

  ## Examples

      iex> get_kill_time(%KillmailData{kill_time: ~U[2023-01-01 12:00:00Z]})
      ~U[2023-01-01 12:00:00Z]

      iex> get_kill_time(%{esi_data: %{"killmail_time" => "2023-01-01T12:00:00Z"}})
      ~U[2023-01-01 12:00:00Z]
  """
  @spec get_kill_time(killmail_source()) :: DateTime.t() | nil
  def get_kill_time(%KillmailData{kill_time: time}) when not is_nil(time), do: time
  def get_kill_time(%KillmailResource{kill_time: time}) when not is_nil(time), do: time

  def get_kill_time(%{esi_data: %{"killmail_time" => time}}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  def get_kill_time(%{kill_time: time}) when not is_nil(time), do: time
  def get_kill_time(%{"kill_time" => time}) when not is_nil(time), do: time

  def get_kill_time(%{"killmail_time" => time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  def get_kill_time(_), do: nil

  @doc """
  Gets the zKillboard data from various killmail data formats.

  ## Examples

      iex> get_zkb_data(%KillmailData{zkb_data: %{"totalValue" => 1000000}})
      %{"totalValue" => 1000000}

      iex> get_zkb_data(%{zkb: %{"totalValue" => 1000000}})
      %{"totalValue" => 1000000}
  """
  @spec get_zkb_data(killmail_source()) :: map()
  def get_zkb_data(%KillmailData{zkb_data: zkb}) when not is_nil(zkb), do: zkb
  def get_zkb_data(%{zkb_data: zkb}) when not is_nil(zkb), do: zkb
  def get_zkb_data(%{zkb: zkb}) when not is_nil(zkb), do: zkb
  def get_zkb_data(%{"zkb_data" => zkb}) when not is_nil(zkb), do: zkb
  def get_zkb_data(%{"zkb" => zkb}) when not is_nil(zkb), do: zkb
  def get_zkb_data(_), do: %{}

  @doc """
  Gets debug data from various killmail data formats for logging and diagnostics.

  Returns a map with these fields:
  - `killmail_id`: The killmail ID
  - `system_id`: The solar system ID
  - `system_name`: The solar system name
  - `has_victim_data`: Whether victim data is present
  - `has_attacker_data`: Whether attacker data is present
  - `attacker_count`: The number of attackers

  ## Examples

      iex> debug_data = debug_data(killmail)
      iex> debug_data.killmail_id
      12345
      iex> debug_data.system_name
      "Jita"
  """
  @spec debug_data(killmail_source()) :: map()
  def debug_data(killmail) do
    # Extract all the relevant fields
    killmail_id = get_killmail_id(killmail)
    system_id = get_system_id(killmail)
    system_name = get_system_name(killmail)
    victim = get_victim(killmail)
    attackers = get_attackers(killmail)

    # Build debug data map
    %{
      killmail_id: killmail_id,
      system_id: system_id,
      system_name: system_name,
      has_victim_data: victim != nil && victim != %{},
      has_attacker_data: attackers != nil && attackers != [],
      attacker_count: if(is_list(attackers), do: length(attackers), else: 0)
    }
  end

  @doc """
  Gets a specific field from the killmail using string keys.

  ## Examples

      iex> get(killmail, "solar_system_name")
      "Jita"
  """
  @spec get(killmail_source(), String.t()) :: any()
  def get(%KillmailData{} = killmail, key) when is_binary(key) do
    Map.get(killmail, String.to_atom(key))
  end

  def get(%KillmailResource{} = killmail, key) when is_binary(key) do
    Map.get(killmail, String.to_atom(key))
  end

  def get(%{esi_data: esi_data}, key) when is_binary(key) and is_map(esi_data) do
    Map.get(esi_data, key)
  end

  def get(data, key) when is_map(data) and is_binary(key) do
    Map.get(data, key)
  end

  def get(_data, _key), do: nil

  @doc """
  Find a field in killmail data based on the character ID and role.
  Used to locate ship and character data in the appropriate place.

  ## Examples

      iex> find_field(killmail, "ship_type_name", 12345, :victim)
      "Retriever"

      iex> find_field(killmail, "ship_type_name", 12345, :attacker)
      "Maller"
  """
  @spec find_field(killmail_source(), String.t(), integer() | String.t(), atom()) :: any()
  def find_field(killmail, field, character_id, :victim) do
    victim = get_victim(killmail)

    if victim_has_character_id?(victim, character_id) do
      Map.get(victim, field)
    else
      nil
    end
  end

  def find_field(killmail, field, character_id, :attacker) do
    attackers = get_attackers(killmail)

    attacker =
      Enum.find(attackers, fn a ->
        attacker_id = Map.get(a, "character_id")
        to_string(attacker_id) == to_string(character_id)
      end)

    if attacker, do: Map.get(attacker, field), else: nil
  end

  def find_field(_killmail, _field, _character_id, _role), do: nil

  # Helper to check if a victim has the given character_id
  defp victim_has_character_id?(victim, character_id) when is_map(victim) do
    victim_id = Map.get(victim, "character_id")
    to_string(victim_id) == to_string(character_id)
  end

  defp victim_has_character_id?(_, _), do: false

  @doc """
  Alias for get_attackers to maintain compatibility with legacy code.
  """
  @spec get_attacker(killmail_source()) :: list(map())
  def get_attacker(killmail), do: get_attackers(killmail)
end
