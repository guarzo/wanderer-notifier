#!/usr/bin/env elixir

# Test script to run outside IEx to debug killmail API
require Logger

IO.puts("Testing Wanderer Kills API...")

# Test system kills endpoint
system_url = "http://host.docker.internal:4004/api/v1/kills/system/30000142?limit=1&since_hours=168"
IO.puts("Fetching from: #{system_url}")

case Req.get(system_url) do
  {:ok, response} ->
    IO.puts("System kills - Status: #{response.status}")
    if response.status == 200 do
      case response.body do
        %{"data" => %{"kills" => kills}} when length(kills) > 0 ->
          kill = hd(kills)
          killmail_id = kill["killmail_id"]
          IO.puts("Found killmail: #{killmail_id}")
          
          # Test detailed killmail
          detail_url = "http://host.docker.internal:4004/api/v1/killmail/#{killmail_id}"
          IO.puts("Fetching details from: #{detail_url}")
          
          case Req.get(detail_url) do
            {:ok, detail_response} ->
              IO.puts("Detail - Status: #{detail_response.status}")
              if detail_response.status == 200 do
                case detail_response.body do
                  %{"data" => kill_data} ->
                    victim = kill_data["victim"]
                    char_name = victim["character_name"] || "Unknown"
                    corp_ticker = get_in(victim, ["corporation", "ticker"]) || "UNKN"
                    ship_name = victim["ship_name"] || "Unknown Ship"
                    IO.puts("SUCCESS - Character: #{char_name} (#{corp_ticker}) - Ship: #{ship_name}")
                  _ ->
                    IO.puts("Unexpected detail response structure")
                end
              else
                IO.puts("Detail request failed: #{detail_response.status}")
              end
            {:error, reason} ->
              IO.puts("Detail request error: #{inspect(reason)}")
          end
          
        _ ->
          IO.puts("No kills found in response")
      end
    else
      IO.puts("System kills request failed: #{response.status}")
    end
  {:error, reason} ->
    IO.puts("System kills request error: #{inspect(reason)}")
end