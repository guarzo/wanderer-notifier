defmodule WandererNotifier.API.APITest do
  use ExUnit.Case, async: true
  import Mox
  alias WandererNotifier.Test.Fixtures.ApiResponses

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "uses fixtures for API testing" do
    WandererNotifier.HTTPMock
    |> expect(:get, fn "https://api.example.com/systems", [], [] ->
      {:ok, %{status_code: 200, body: "[]"}}
    end)
    |> expect(:get, fn "https://api.example.com/characters", [], [] ->
      {:ok, %{status_code: 200, body: ApiResponses.esi_character_response()}}
    end)

    result =
      WandererNotifier.HTTPMock.get("https://api.example.com/systems", [], [])

    assert {:ok, %{status_code: 200, body: "[]"}} = result

    char_result =
      WandererNotifier.HTTPMock.get("https://api.example.com/characters", [], [])

    assert {:ok, %{status_code: 200, body: char_body}} = char_result
    assert char_body["character_id"] == 12_345
    assert char_body["name"] == "Test Character"
  end
end
