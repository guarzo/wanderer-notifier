# This script tests the recent TPS data endpoint with a direct HTTP request
# Run with: elixir scripts/test_recent_tps.exs

# Required dependencies
Mix.install([
  {:httpoison, "~> 1.8"},
  {:jason, "~> 1.3"}
])

# Configuration - replace with your actual values or use environment variables
api_url = System.get_env("CORP_TOOLS_API_URL") || "https://your-api-url"
api_token = System.get_env("CORP_TOOLS_API_TOKEN") || "your-token"

# Function to make the request
defmodule TpsTest do
  def test_recent_tps_data do
    url = "#{api_url}/recent-tps-data"

    headers = [
      {"Authorization", "Bearer #{api_token}"},
      {"Content-Type", "application/json"}
    ]

    IO.puts("Making request to #{url}")

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        IO.puts("Request successful (200 OK)")
        case Jason.decode(body) do
          {:ok, data} ->
            IO.puts("Successfully decoded JSON response")
            IO.puts("Data keys: #{inspect(Map.keys(data))}")

            # Check if expected keys exist
            check_key(data, "KillsByShipType")
            check_key(data, "KillsByMonth")
            check_key(data, "TotalValue")

            {:ok, data}

          {:error, error} ->
            IO.puts("Failed to parse JSON response: #{inspect(error)}")
            IO.puts("Raw response body: #{body}")
            {:error, "Failed to parse response"}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        IO.puts("Request failed with status code #{status}")
        IO.puts("Response body: #{body}")
        {:error, "HTTP Status #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_key(data, key) do
    if Map.has_key?(data, key) do
      value = data[key]
      case value do
        val when is_map(val) ->
          keys = Map.keys(val) |> Enum.take(5)
          IO.puts("Found #{key} with #{map_size(val)} entries. Sample keys: #{inspect(keys)}")

        val when is_list(val) ->
          IO.puts("Found #{key} with #{length(val)} items")

        val ->
          IO.puts("Found #{key} with value: #{inspect(val)}")
      end
    else
      IO.puts("Key '#{key}' not found in response")
    end
  end
end

# Execute the test
TpsTest.test_recent_tps_data()
