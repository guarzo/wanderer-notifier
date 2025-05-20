defmodule WandererNotifier.Test.Support.Helpers.ESIMockHelper do
  @moduledoc """
  Helper module for setting up ESI service mocks in tests.
  """

  import Mox

  alias WandererNotifier.ESI.ServiceMock

  @doc """
  Sets up common ESI service mocks for testing.
  """
  def setup_esi_mocks do
    ServiceMock
    |> stub(:get_character_info, fn id, _opts ->
      case id do
        100 -> {:ok, %{"name" => "Victim", "corporation_id" => 300, "alliance_id" => 400}}
        101 -> {:ok, %{"name" => "Attacker", "corporation_id" => 301, "alliance_id" => 401}}
        _ -> {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}
      end
    end)
    |> stub(:get_corporation_info, fn id, _opts ->
      case id do
        300 -> {:ok, %{"name" => "Victim Corp", "ticker" => "VC"}}
        301 -> {:ok, %{"name" => "Attacker Corp", "ticker" => "AC"}}
        _ -> {:ok, %{"name" => "Unknown Corp", "ticker" => "UC"}}
      end
    end)
    |> stub(:get_alliance_info, fn id, _opts ->
      case id do
        400 -> {:ok, %{"name" => "Victim Alliance", "ticker" => "VA"}}
        401 -> {:ok, %{"name" => "Attacker Alliance", "ticker" => "AA"}}
        _ -> {:ok, %{"name" => "Unknown Alliance", "ticker" => "UA"}}
      end
    end)
    |> stub(:get_type_info, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)
    |> stub(:get_system, fn id, _opts ->
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
    end)
    |> stub(:get_killmail, fn kill_id, killmail_hash, _opts ->
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
    end)
  end
end
