defmodule WandererNotifier.HTTPTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  test "mocks HTTP client successfully" do
    WandererNotifier.HTTPMock
    |> expect(:get, fn "https://example.com", [], [] ->
      {:ok, %{status_code: 200, body: "OK"}}
    end)

    result = WandererNotifier.HTTPMock.get("https://example.com", [], [])
    assert {:ok, %{status_code: 200, body: "OK"}} = result
  end
end
