defmodule WandererNotifier.API.APITest do
  use ExUnit.Case, async: true
  import Mox
  alias WandererNotifier.Test.Fixtures.ApiResponses

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "uses fixtures for API testing" do
    WandererNotifier.HTTPMock
    |> expect(:request, fn :get, "https://api.example.com/systems", nil, [], [] ->
      {:ok, %{status_code: 200, body: "[]"}}
    end)
    |> expect(:request, fn :get, "https://api.example.com/characters", nil, [], [] ->
      {:ok, %{status_code: 200, body: ApiResponses.esi_character_response()}}
    end)

    result =
      WandererNotifier.HTTPMock.request(:get, "https://api.example.com/systems", nil, [], [])

    assert {:ok, %{status_code: 200, body: "[]"}} = result

    char_result =
      WandererNotifier.HTTPMock.request(:get, "https://api.example.com/characters", nil, [], [])

    assert {:ok, %{status_code: 200, body: char_body}} = char_result
    assert char_body["character_id"] == 12_345
    assert char_body["name"] == "Test Character"
  end
end
