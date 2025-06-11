defmodule WandererNotifier.HTTPTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.HTTPMock, as: HttpClientMock
  alias WandererNotifier.HTTP

  setup :verify_on_exit!

  test "mocks HTTP client successfully" do
    WandererNotifier.HttpClient.HttpoisonMock
    |> expect(:get, fn "https://example.com", [], [] ->
      {:ok, %{status_code: 200, body: "OK"}}
    end)

    result = WandererNotifier.HttpClient.HttpoisonMock.get("https://example.com", [], [])
    assert {:ok, %{status_code: 200, body: "OK"}} = result
  end
end
