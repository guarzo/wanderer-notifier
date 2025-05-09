defmodule WandererNotifier.ESI.ServiceMock do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  @behaviour WandererNotifier.ESI.ServiceBehaviour

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
  @error_id 99999
  @not_found_id 88888
  @service_unavailable_id 77777

  # Implement behaviour functions
  @impl true
  def get_killmail(@error_id, _hash), do: {:error, :unknown_error}
  def get_killmail(@not_found_id, _hash), do: {:error, :not_found}
  def get_killmail(@service_unavailable_id, _hash), do: {:error, :service_unavailable}

  def get_killmail(_killmail_id, _hash) do
    {:ok,
     %{
       "victim" => %{
         "character_id" => 123,
         "corporation_id" => 456,
         "ship_type_id" => 789
       },
       "solar_system_id" => 30_000_142,
       "attackers" => []
     }}
  end

  @impl true
  def get_character_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_character_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_character_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}

  def get_character_info(_id, _opts) do
    {:ok, @character_data}
  end

  @impl true
  def get_corporation_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_corporation_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_corporation_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}

  def get_corporation_info(_id, _opts) do
    {:ok, @corporation_data}
  end

  @impl true
  def get_alliance_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_alliance_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_alliance_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}

  def get_alliance_info(_id, _opts) do
    {:ok, @alliance_data}
  end

  @impl true
  def get_system_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_system_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_system_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}

  def get_system_info(_id, _opts) do
    {:ok, @system_data}
  end

  @impl true
  def get_system(@error_id), do: {:error, :unknown_error}
  def get_system(@not_found_id), do: {:error, :not_found}
  def get_system(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_system(_system_id), do: {:ok, @system_data}

  @impl true
  def get_system(@error_id, _opts), do: {:error, :unknown_error}
  def get_system(@not_found_id, _opts), do: {:error, :not_found}
  def get_system(@service_unavailable_id, _opts), do: {:error, :service_unavailable}

  def get_system(_system_id, _opts) do
    {:ok, @system_data}
  end

  @impl true
  def get_type_info(@error_id), do: {:error, :unknown_error}
  def get_type_info(@not_found_id), do: {:error, :not_found}
  def get_type_info(@service_unavailable_id), do: {:error, :service_unavailable}
  def get_type_info(_type_id), do: {:ok, @ship_data}

  @impl true
  def get_type_info(@error_id, _opts), do: {:error, :unknown_error}
  def get_type_info(@not_found_id, _opts), do: {:error, :not_found}
  def get_type_info(@service_unavailable_id, _opts), do: {:error, :service_unavailable}

  def get_type_info(_type_id, _opts) do
    {:ok, @ship_data}
  end

  @impl true
  def get_character(@error_id), do: {:error, :unknown_error}
  def get_character(@not_found_id), do: {:error, :not_found}
  def get_character(@service_unavailable_id), do: {:error, :service_unavailable}

  def get_character(_character_id) do
    {:ok, @character_data}
  end

  @impl true
  def get_type(@error_id), do: {:error, :unknown_error}
  def get_type(@not_found_id), do: {:error, :not_found}
  def get_type(@service_unavailable_id), do: {:error, :service_unavailable}

  def get_type(_type_id) do
    {:ok, @ship_data}
  end

  @impl true
  def get_ship_type_name(@error_id), do: {:error, :unknown_error}
  def get_ship_type_name(@not_found_id), do: {:error, :not_found}
  def get_ship_type_name(@service_unavailable_id), do: {:error, :service_unavailable}

  def get_ship_type_name(_ship_type_id) do
    {:ok, @ship_data}
  end

  @impl true
  def get_system_kills(@error_id, _limit), do: {:error, :unknown_error}
  def get_system_kills(@not_found_id, _limit), do: {:error, :not_found}
  def get_system_kills(@service_unavailable_id, _limit), do: {:error, :service_unavailable}

  def get_system_kills(_system_id, _limit) do
    {:ok, []}
  end
end
