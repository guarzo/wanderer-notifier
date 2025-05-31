defmodule WandererNotifier.Killmail.Processing.EnrichmentTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.ESI.ServiceMock
  alias WandererNotifier.TestMocks

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up application environment
    Application.put_env(:wanderer_notifier, :esi_service, ServiceMock)

    # Set up default stubs
    TestMocks.setup_default_stubs()

    # Add expectations for ESI client calls
    ServiceMock
    |> stub(:get_character_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Character"}}
    end)
    |> stub(:get_corporation_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)
    |> stub(:get_alliance_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "TEST"}}
    end)
    |> stub(:get_universe_type, fn _type_id, _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)
    |> stub(:get_type_info, fn _type_id, _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)
    |> stub(:get_system, fn _id, _opts ->
      {:ok,
       %{
         "system_id" => 30_000_142,
         "name" => "Test System",
         "security_status" => 0.5
       }}
    end)
    |> stub(:get_killmail, fn _id, _hash, _opts ->
      {:ok,
       %{
         "killmail_id" => 123,
         "killmail_time" => "2023-01-01T12:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 100,
           "corporation_id" => 300,
           "alliance_id" => 400,
           "ship_type_id" => 200
         },
         "attackers" => []
       }}
    end)

    :ok
  end

  describe "enrich_killmail_data/1" do
    test "enriches killmail data" do
      killmail = %Killmail{
        killmail_id: 123,
        zkb: %{"hash" => "testhash"},
        esi_data: %{
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => 100,
            "corporation_id" => 300,
            "alliance_id" => 400,
            "ship_type_id" => 200
          },
          "value" => 150_000_000,
          "attackers" => []
        }
      }

      assert {:ok, enriched_killmail} = Enrichment.enrich_killmail_data(killmail)
      assert enriched_killmail.victim_name == "Test Character"
      assert enriched_killmail.victim_corporation == "Test Corporation"
      assert enriched_killmail.victim_corp_ticker == "TEST"
      assert enriched_killmail.victim_alliance == "Test Alliance"
      assert enriched_killmail.ship_name == "Test Ship"
      assert enriched_killmail.system_name == "Test System"
      assert enriched_killmail.system_id == 30_000_142
    end
  end
end
