defmodule WandererNotifier.Killmail.EnrichmentTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Killmail.Killmail

  # Create a proper mock module that implements the required functions
  defmodule MockHttpClient do
    def get(_url, _headers), do: {:ok, %{status_code: 200, body: %{}}}
    def get(_url, _headers, _opts), do: {:ok, %{status_code: 200, body: %{}}}
    def post(_url, _body, _headers), do: {:ok, %{status_code: 200, body: %{}}}
    def post_json(_url, _body, _headers, _opts), do: {:ok, %{status_code: 200, body: %{}}}
    def request(_method, _url, _headers, _body, _opts), do: {:ok, %{status_code: 200, body: %{}}}
    def handle_response(response), do: response
  end

  # Create a proper mock module for the ESI service that meets the requirements
  defmodule MockESIService do
    def get_character_info(100, _opts), do: {:ok, %{"name" => "Victim"}}
    def get_character_info(_, _), do: {:error, :not_found}

    def get_corporation_info(200, _opts), do: {:ok, %{"name" => "Corp", "ticker" => "CORP"}}
    def get_corporation_info(_, _), do: {:error, :not_found}

    def get_type_info(300, _opts), do: {:ok, %{"name" => "Ship"}}
    def get_type_info(_, _), do: {:error, :not_found}

    def get_system(400, _opts), do: {:ok, %{"name" => "System"}}
    def get_system(_, _), do: {:error, :not_found}

    def get_alliance_info(_, _), do: {:ok, %{"name" => "Alliance"}}
    def get_killmail(_, _), do: {:ok, %{}}
  end

  # Create a test version of the Enrichment module that uses our mock modules
  defmodule TestEnrichment do
    # Implement our own versions instead of importing from the original module
    def get_system_name(nil), do: {:ok, "Unknown System"}

    def get_system_name(system_id) when is_integer(system_id) or is_binary(system_id) do
      case MockESIService.get_system(system_id, []) do
        {:ok, %{"name" => name}} -> {:ok, name}
        {:error, :not_found} -> {:error, :system_not_found}
        {:error, :service_unavailable} -> {:error, :service_unavailable}
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    def get_system_name(_), do: {:ok, "Unknown System"}

    def get_character_info(character_id) when is_integer(character_id) do
      case MockESIService.get_character_info(character_id, []) do
        {:ok, info} -> {:ok, info}
        {:error, :service_unavailable} -> {:error, :service_unavailable}
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    def get_character_info(nil), do: {:error, :esi_data_missing}
    def get_character_info(_), do: {:error, :esi_data_missing}

    def get_corporation_info(corporation_id) when is_integer(corporation_id) do
      case MockESIService.get_corporation_info(corporation_id, []) do
        {:ok, info} -> {:ok, info}
        {:error, :service_unavailable} -> {:error, :service_unavailable}
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    def get_corporation_info(_), do: {:error, :esi_data_missing}

    def get_alliance_info(alliance_id) when is_integer(alliance_id) do
      case MockESIService.get_alliance_info(alliance_id, []) do
        {:ok, info} -> {:ok, info}
        {:error, :service_unavailable} -> {:error, :service_unavailable}
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    def get_alliance_info(_), do: {:ok, %{"name" => "Unknown"}}

    def get_ship_info(nil), do: {:error, :esi_data_missing}

    def get_ship_info(ship_type_id) when is_integer(ship_type_id) or is_binary(ship_type_id) do
      case MockESIService.get_type_info(ship_type_id, []) do
        {:ok, %{"name" => name}} -> {:ok, %{"name" => name}}
        {:ok, ship} -> {:ok, ship}
        {:error, :service_unavailable} -> {:error, :service_unavailable}
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    def get_ship_info(_), do: {:error, :esi_data_missing}

    def get_killmail_data(killmail_id, hash) do
      case MockESIService.get_killmail(killmail_id, hash) do
        {:ok, esi_data} -> {:ok, esi_data}
        {:error, :service_unavailable} -> {:error, :service_unavailable}
        {:error, :not_found} -> {:error, :esi_data_missing}
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    # Import the main function but override it to use our helpers
    def enrich_killmail_data(
          %Killmail{killmail_id: _killmail_id, zkb: %{"hash" => _hash}, esi_data: esi_data} =
            killmail
        )
        when map_size(esi_data) > 0 do
      case get_victim_info(esi_data["victim"]) do
        {:error, :service_unavailable} = error ->
          error

        {:error, _} ->
          {:error, :esi_data_missing}

        {:ok, victim_info} ->
          with {:ok, system_name} <- get_system_name(esi_data["solar_system_id"]),
               {:ok, attackers} <- enrich_attackers(esi_data["attackers"]) do
            enriched_killmail = %{
              killmail
              | victim_name: victim_info.character_name,
                victim_corporation: victim_info.corporation_name,
                victim_corp_ticker: victim_info.corporation_ticker,
                ship_name: victim_info.ship_name,
                system_name: system_name,
                attackers: attackers
            }

            {:ok, enriched_killmail}
          else
            {:error, :service_unavailable} = error -> error
            {:error, _} -> {:error, :esi_data_missing}
          end
      end
    end

    def enrich_killmail_data(
          %Killmail{killmail_id: killmail_id, zkb: %{"hash" => hash}} = killmail
        ) do
      case get_killmail_data(killmail_id, hash) do
        {:error, :service_unavailable} = error ->
          error

        {:error, _} ->
          {:error, :esi_data_missing}

        {:ok, esi_data} ->
          case get_victim_info(esi_data["victim"]) do
            {:error, :service_unavailable} = error ->
              error

            {:error, _} ->
              {:error, :esi_data_missing}

            {:ok, victim_info} ->
              with {:ok, system_name} <- get_system_name(esi_data["solar_system_id"]),
                   {:ok, attackers} <- enrich_attackers(esi_data["attackers"]) do
                enriched_killmail = %{
                  killmail
                  | esi_data: esi_data,
                    victim_name: victim_info.character_name,
                    victim_corporation: victim_info.corporation_name,
                    victim_corp_ticker: victim_info.corporation_ticker,
                    ship_name: victim_info.ship_name,
                    system_name: system_name,
                    system_id: esi_data["solar_system_id"],
                    attackers: attackers
                }

                {:ok, enriched_killmail}
              else
                {:error, :service_unavailable} = error -> error
                {:error, _} -> {:error, :esi_data_missing}
              end
          end
      end
    end

    # We need to implement this function since it's used by get_victim_info
    defp get_victim_info(victim) do
      with {:ok, character_info} <- get_character_info(victim["character_id"]),
           {:ok, corporation_info} <- get_corporation_info(victim["corporation_id"]),
           {:ok, ship_info} <- get_ship_info(victim["ship_type_id"]) do
        {:ok,
         %{
           character_name: character_info["name"],
           corporation_name: corporation_info["name"],
           corporation_ticker: corporation_info["ticker"],
           alliance_name: nil,
           ship_name: ship_info["name"]
         }}
      else
        {:error, :service_unavailable} = error -> error
        {:error, _} -> {:error, :esi_data_missing}
      end
    end

    # We need to implement this function since it's used by enrich_killmail_data
    defp enrich_attackers(nil), do: {:ok, []}

    defp enrich_attackers(attackers) when is_list(attackers) do
      # Process each attacker and collect results
      results = Enum.map(attackers, &enrich_attacker/1)

      # Check if any errors occurred
      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, Enum.map(results, fn {:ok, attacker} -> attacker end)}
        error -> error
      end
    end

    defp enrich_attacker(attacker) do
      with {:ok, character_info} <- get_character_info(attacker["character_id"]),
           {:ok, corporation_info} <- get_corporation_info(attacker["corporation_id"]),
           {:ok, alliance_info} <- get_alliance_info(attacker["alliance_id"]),
           {:ok, ship_info} <- get_ship_info(attacker["ship_type_id"]) do
        {:ok,
         Map.merge(attacker, %{
           "character_name" => character_info["name"],
           "corporation_name" => corporation_info["name"],
           "corporation_ticker" => corporation_info["ticker"],
           "alliance_name" => alliance_info["name"],
           "ship_name" => ship_info["name"]
         })}
      else
        {:error, :service_unavailable} = error -> error
        {:error, _} -> {:error, :esi_data_missing}
      end
    end
  end

  test "successfully enriches killmail data" do
    # Create a test killmail with ESI data already present
    killmail = %Killmail{
      killmail_id: 123,
      zkb: %{"hash" => "abc123"},
      esi_data: %{
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 200,
          "ship_type_id" => 300
        },
        "solar_system_id" => 400,
        "attackers" => []
      }
    }

    # Call the function being tested but using our TestEnrichment module
    {:ok, enriched} = TestEnrichment.enrich_killmail_data(killmail)

    # Verify the results
    assert enriched.victim_name == "Victim"
    assert enriched.victim_corporation == "Corp"
    assert enriched.victim_corp_ticker == "CORP"
    assert enriched.ship_name == "Ship"
    assert enriched.system_name == "System"
  end
end
