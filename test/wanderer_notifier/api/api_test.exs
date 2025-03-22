defmodule WandererNotifier.ApiTest do
  use ExUnit.Case
  import Mox
  alias WandererNotifier.Test.Fixtures.ApiResponses

  setup :verify_on_exit!

  test "uses fixtures for API testing" do
    # Set up mock with specific expectations for each URL
    WandererNotifier.MockHTTP
    |> expect(:get, fn url, _headers, _options ->
      assert String.contains?(url, "/systems")
      {:ok, %{status: 200, body: ApiResponses.map_systems_response(), headers: []}}
    end)
    |> expect(:get, fn url, _headers, _options ->
      assert String.contains?(url, "/characters")
      {:ok, %{status: 200, body: ApiResponses.esi_character_response(), headers: []}}
    end)

    # Test systems endpoint
    systems_result = WandererNotifier.MockHTTP.get("https://api.example.com/systems", [], [])
    assert {:ok, %{status: 200, body: systems_body}} = systems_result
    assert length(systems_body["systems"]) == 2
    assert Enum.at(systems_body["systems"], 0)["name"] == "Test System"

    # Test characters endpoint
    char_result = WandererNotifier.MockHTTP.get("https://api.example.com/characters", [], [])
    assert {:ok, %{status: 200, body: char_body}} = char_result
    assert char_body["character_id"] == 12_345
    assert char_body["name"] == "Test Character"
  end
end
