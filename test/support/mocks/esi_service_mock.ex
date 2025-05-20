defmodule WandererNotifier.ESI.ServiceMock do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  # Default test data
  @character_data %{
    "name" => "Test Character",
    "corporation_id" => 456
  }

  @corporation_data %{
    "name" => "Test Corporation",
    "ticker" => "TEST",
    "alliance_id" => 789
  }

  @alliance_data %{
    "name" => "Test Alliance"
  }

  @system_data %{
    "name" => "Test System"
  }

  @ship_data %{
    "name" => "Test Ship"
  }

  # Special test IDs for error cases
  @error_id 99_999
  @not_found_id 88_888
  @service_unavailable_id 77_777

  def get_killmail(@error_id, _hash), do: {:error, :unknown_error}
  def get_killmail(@not_found_id, _hash), do: {:error, :not_found}
  def get_killmail(@service_unavailable_id, _hash), do: {:error, :service_unavailable}

  def get_killmail(kill_id, hash) when is_binary(kill_id) or is_integer(kill_id),
    do: {:ok, %{"killmail_id" => kill_id, "killmail_hash" => hash}}

  def get_killmail(_, _), do: {:error, :invalid_kill_id}

  def get_killmail(@error_id, _hash, _opts), do: {:error, :unknown_error}
  def get_killmail(@not_found_id, _hash, _opts), do: {:error, :not_found}
  def get_killmail(@service_unavailable_id, _hash, _opts), do: {:error, :service_unavailable}

  def get_killmail(kill_id, kill_hash, _opts) do
    {:ok,
     %{
       "killmail_id" => kill_id,
       "killmail_hash" => kill_hash,
       "killmail_time" => "2024-01-01T00:00:00Z",
       "victim" => %{
         "character_id" => 123_456,
         "corporation_id" => 789_012,
         "alliance_id" => 345_678,
         "ship_type_id" => 670
       },
       "attackers" => [
         %{
           "character_id" => 234_567,
           "corporation_id" => 890_123,
           "alliance_id" => 456_789,
           "ship_type_id" => 670,
           "weapon_type_id" => 1234,
           "final_blow" => true
         }
       ],
       "solar_system_id" => 30_000_142,
       "war_id" => nil
     }}
  end

  def get_character_info(@error_id), do: {:error, :unknown_error}
  def get_character_info(@not_found_id), do: {:error, :not_found}
  def get_character_info(@service_unavailable_id), do: {:error, :service_unavailable}

  def get_character_info(character_id) when is_binary(character_id) or is_integer(character_id),
    do: {:ok, @character_data}

  def get_character_info(_), do: {:error, :invalid_character_id}

  def get_character_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_character_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_character_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_character_info(_id, _opts), do: {:ok, @character_data}

  def get_character(@error_id), do: {:error, :unknown_error}
  def get_character(@not_found_id), do: {:error, :not_found}
  def get_character(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_character(_character_id), do: {:ok, @character_data}

  def get_character(@error_id, _opts), do: {:error, :unknown_error}
  def get_character(@not_found_id, _opts), do: {:error, :not_found}
  def get_character(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_character(_character_id, _opts), do: {:ok, @character_data}

  def get_corporation_info(@error_id), do: {:error, :unknown_error}
  def get_corporation_info(@not_found_id), do: {:error, :not_found}
  def get_corporation_info(@service_unavailable_id), do: {:error, :service_unavailable}

  def get_corporation_info(corporation_id)
      when is_binary(corporation_id) or is_integer(corporation_id),
      do: {:ok, @corporation_data}

  def get_corporation_info(_), do: {:error, :invalid_corporation_id}

  def get_corporation_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_corporation_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_corporation_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_corporation_info(_id, _opts), do: {:ok, @corporation_data}

  # Alliance functions
  def get_alliance_info(@error_id), do: {:error, :unknown_error}
  def get_alliance_info(@not_found_id), do: {:error, :not_found}
  def get_alliance_info(@service_unavailable_id), do: {:error, :service_unavailable}

  def get_alliance_info(alliance_id) when is_binary(alliance_id) or is_integer(alliance_id),
    do: {:ok, @alliance_data}

  def get_alliance_info(_), do: {:error, :invalid_alliance_id}

  def get_alliance_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_alliance_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_alliance_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_alliance_info(_id, _opts), do: {:ok, @alliance_data}

  # System functions
  def get_system(@error_id), do: {:error, :unknown_error}
  def get_system(@not_found_id), do: {:error, :not_found}
  def get_system(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_system(nil), do: {:ok, %{"name" => "Unknown", "system_id" => nil}}

  def get_system(system_id) when is_binary(system_id) or is_integer(system_id),
    do: {:ok, %{"name" => "Test System", "system_id" => system_id}}

  def get_system(_), do: {:error, :invalid_system_id}

  def get_system(@error_id, _opts), do: {:error, :unknown_error}
  def get_system(@not_found_id, _opts), do: {:error, :not_found}
  def get_system(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_system(nil, _opts), do: {:ok, %{"name" => "Unknown", "system_id" => nil}}

  def get_system(system_id, _opts),
    do: {:ok, %{"name" => "Test System", "system_id" => system_id}}

  def get_system_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_system_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_system_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_system_info(_id, _opts), do: {:ok, @system_data}

  def get_ship_type_name(@error_id), do: {:error, :unknown_error}
  def get_ship_type_name(@not_found_id), do: {:error, :not_found}
  def get_ship_type_name(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_ship_type_name(_ship_type_id), do: {:ok, @ship_data}

  def get_ship_type_name(@error_id, _opts), do: {:error, :unknown_error}
  def get_ship_type_name(@not_found_id, _opts), do: {:error, :not_found}
  def get_ship_type_name(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_ship_type_name(_ship_type_id, _opts), do: {:ok, @ship_data}

  def get_type(@error_id), do: {:error, :unknown_error}
  def get_type(@not_found_id), do: {:error, :not_found}
  def get_type(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_type(_type_id), do: {:ok, @ship_data}

  def get_type(@error_id, _opts), do: {:error, :unknown_error}
  def get_type(@not_found_id, _opts), do: {:error, :not_found}
  def get_type(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_type(_type_id, _opts), do: {:ok, @ship_data}

  def get_type_info(@error_id), do: {:error, :unknown_error}
  def get_type_info(@not_found_id), do: {:error, :not_found}
  def get_type_info(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_type_info(_type_id), do: {:ok, @ship_data}

  def get_type_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_type_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_type_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}
  def get_type_info(_type_id, _opts), do: {:ok, @ship_data}

  def get_system_kills(@error_id, _limit, _opts), do: {:error, :unknown_error}
  def get_system_kills(@not_found_id, _limit, _opts), do: {:error, :not_found}
  def get_system_kills(@service_unavailable_id, _limit, _opts), do: {:error, :service_unavailable}

  def get_system_kills(_system_id, limit, _opts) do
    # Generate a list of killmails up to the specified limit
    killmails =
      Enum.map(1..limit, fn i ->
        %{
          "killmail_id" => 100 + i,
          "killmail_hash" => "abc#{i}",
          "killmail_time" => "2020-01-01T00:00:00Z",
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => 100,
            "corporation_id" => 300,
            "alliance_id" => 400,
            "ship_type_id" => 200
          }
        }
      end)

    {:ok, killmails}
  end

  # These functions are stubbed to return :not_implemented because they are not currently used in tests.
  # If you need to test functionality that uses these functions, implement them with appropriate test data.
  @doc """
  Stub for get_universe_type/2. Returns :not_implemented as this function is not currently used in tests.
  """
  def get_universe_type(_id, _opts \\ []), do: {:error, :not_implemented}

  @doc """
  Stub for search/3. Returns :not_implemented as this function is not currently used in tests.
  """
  def search(_category, _search, _opts \\ []), do: {:error, :not_implemented}
end
