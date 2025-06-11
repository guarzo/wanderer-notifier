# Test script to verify the license validation fix
defmodule TestLicenseFix do
  alias WandererNotifier.HttpClient.Utils.JsonUtils

  def test_json_decode do
    # Test case 1: Valid JSON string
    json_string = ~s({"valid_to":"2026-01-20","license_id":"817fb13d-0e04-47f6-8a1b-1cd9cba7a106","license_valid":true,"license_name":"Guarzo Opper","bots":[],"bot_associated":false})
    
    IO.puts("Testing JSON decode with string:")
    IO.inspect(json_string)
    
    case JsonUtils.decode(json_string) do
      {:ok, decoded} ->
        IO.puts("\nDecoded successfully:")
        IO.inspect(decoded)
        IO.puts("\nIs map? #{is_map(decoded)}")
        IO.puts("Has license_valid key? #{Map.has_key?(decoded, "license_valid")}")
      
      {:error, reason} ->
        IO.puts("\nDecode failed: #{inspect(reason)}")
    end
    
    # Test case 2: Already decoded map
    IO.puts("\n\nTesting with already decoded map:")
    map_data = %{"license_valid" => true, "license_name" => "Test"}
    IO.inspect(map_data)
    
    case JsonUtils.decode(map_data) do
      {:ok, decoded} ->
        IO.puts("\nHandled already decoded map correctly:")
        IO.inspect(decoded)
      
      {:error, reason} ->
        IO.puts("\nFailed: #{inspect(reason)}")
    end
  end
end

TestLicenseFix.test_json_decode()