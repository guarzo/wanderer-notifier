# Direct standalone test for characters API
# Run with: elixir lib/direct_test.exs

# Construct the URL directly without any module dependencies
map_url = System.get_env("MAP_URL") || "https://wanderer-test.fly.dev"
map_name = System.get_env("MAP_NAME") || "flygd"
map_token = System.get_env("MAP_TOKEN") || ""

# Parse the URL
uri = URI.parse(map_url)
base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
characters_url = "#{base_url}/api/map/characters?slug=#{map_name}"

IO.puts("Testing direct API call to: #{characters_url}")
IO.puts("Using token: #{if map_token != "", do: "PRESENT", else: "MISSING"}")

# Make the request using only HTTPoison
headers = [
  {"Authorization", "Bearer #{map_token}"},
  {"Content-Type", "application/json"},
  {"Accept", "application/json"}
]

IO.puts("\nMaking API request...")

case HTTPoison.get(characters_url, headers) do
  {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
    IO.puts("API call successful! Status code: 200")
    IO.puts("Body preview: #{String.slice(body, 0, 100)}...")

    # Try to parse JSON
    case Jason.decode(body) do
      {:ok, parsed} ->
        IO.puts("\nJSON parsed successfully")

        # Check if we have characters data
        chars =
          case parsed do
            %{"data" => data} when is_list(data) -> data
            data when is_list(data) -> data
            _ -> []
          end

        IO.puts("Found #{length(chars)} characters")

        if length(chars) > 0 do
          first_char = List.first(chars)
          IO.puts("First character: #{inspect(first_char)}")
        end

      {:error, error} ->
        IO.puts("\nJSON parsing error: #{inspect(error)}")
    end

  {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
    IO.puts("API call failed with status code: #{status_code}")
    IO.puts("Error body: #{body}")

  {:error, %HTTPoison.Error{reason: reason}} ->
    IO.puts("API call error: #{inspect(reason)}")
end
