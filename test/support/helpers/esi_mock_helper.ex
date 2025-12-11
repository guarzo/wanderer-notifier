defmodule WandererNotifier.Test.Support.Helpers.ESIMockHelper do
  @moduledoc """
  Helper module for setting up ESI service mocks in tests.
  """

  import Mox

  alias WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
  alias WandererNotifier.Infrastructure.Adapters.ESI.ClientMock

  @doc """
  Sets up common ESI service mocks for testing.
  """
  def setup_esi_mocks do
    # Setup ServiceMock
    ServiceMock
    |> setup_character_mocks()
    |> setup_corporation_mocks()
    |> setup_alliance_mocks()
    |> setup_type_mocks()
    |> setup_system_mocks()
    |> setup_killmail_mocks()

    # Also setup ClientMock since ESIService uses esi_client() internally
    setup_client_mocks()
  end

  defp setup_client_mocks do
    stub(ClientMock, :get_killmail, &get_killmail/3)
    stub(ClientMock, :get_character_info, &get_character_info/2)
    stub(ClientMock, :get_corporation_info, &get_corporation_info/2)
    stub(ClientMock, :get_alliance_info, &get_alliance_info/2)
    stub(ClientMock, :get_universe_type, &get_type_info/2)
    stub(ClientMock, :get_system, &get_system/2)
    stub(ClientMock, :get_system_kills, fn _id, _limit, _opts -> {:ok, []} end)
    stub(ClientMock, :search_inventory_type, fn _query, _strict -> {:ok, %{}} end)
  end

  defp setup_character_mocks(mock) do
    mock
    |> stub(:get_character_info, &get_character_info/2)
  end

  defp setup_corporation_mocks(mock) do
    mock
    |> stub(:get_corporation_info, &get_corporation_info/2)
  end

  defp setup_alliance_mocks(mock) do
    mock
    |> stub(:get_alliance_info, &get_alliance_info/2)
  end

  defp setup_type_mocks(mock) do
    mock
    |> stub(:get_type_info, &get_type_info/2)
  end

  defp setup_system_mocks(mock) do
    mock
    |> stub(:get_system, &get_system/2)
  end

  defp setup_killmail_mocks(mock) do
    mock
    |> stub(:get_killmail, &get_killmail/3)
  end

  # Mock response functions
  defp get_character_info(id, _opts) do
    case id do
      100 -> {:ok, %{"name" => "Victim", "corporation_id" => 300, "alliance_id" => 400}}
      101 -> {:ok, %{"name" => "Attacker", "corporation_id" => 301, "alliance_id" => 401}}
      _ -> {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}
    end
  end

  defp get_corporation_info(id, _opts) do
    case id do
      300 -> {:ok, %{"name" => "Victim Corp", "ticker" => "VC"}}
      301 -> {:ok, %{"name" => "Attacker Corp", "ticker" => "AC"}}
      _ -> {:ok, %{"name" => "Unknown Corp", "ticker" => "UC"}}
    end
  end

  defp get_alliance_info(id, _opts) do
    case id do
      400 -> {:ok, %{"name" => "Victim Alliance", "ticker" => "VA"}}
      401 -> {:ok, %{"name" => "Attacker Alliance", "ticker" => "AA"}}
      _ -> {:ok, %{"name" => "Unknown Alliance", "ticker" => "UA"}}
    end
  end

  defp get_type_info(id, _opts) do
    case id do
      200 -> {:ok, %{"name" => "Victim Ship"}}
      201 -> {:ok, %{"name" => "Attacker Ship"}}
      301 -> {:ok, %{"name" => "Weapon"}}
      _ -> {:ok, %{"name" => "Unknown Ship"}}
    end
  end

  defp get_system(id, _opts) do
    case id do
      30_000_142 ->
        {:ok,
         %{
           "name" => "Test System",
           "system_id" => 30_000_142,
           "constellation_id" => 20_000_020,
           "security_status" => 0.9,
           "security_class" => "B"
         }}

      _ ->
        {:error, :not_found}
    end
  end

  defp get_killmail(kill_id, killmail_hash, _opts) do
    case {kill_id, killmail_hash} do
      {123, "abc123"} ->
        {:ok,
         %{
           "killmail_id" => 123,
           "killmail_time" => "2024-01-01T00:00:00Z",
           "solar_system_id" => 30_000_142,
           "victim" => %{
             "character_id" => 100,
             "corporation_id" => 300,
             "alliance_id" => 400,
             "ship_type_id" => 200
           },
           "attackers" => []
         }}

      _ ->
        {:error, :killmail_not_found}
    end
  end
end
