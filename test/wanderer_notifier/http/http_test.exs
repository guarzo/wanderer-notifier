defmodule WandererNotifier.HttpTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "mocks HTTP client successfully" do
    # Set up mock expectation
    WandererNotifier.MockHTTP
    |> expect(:get, fn _url, _headers, _options ->
      {:ok, %{status: 200, body: %{"message" => "Test successful"}, headers: []}}
    end)

    # Verify that the mock works when called
    result = WandererNotifier.MockHTTP.get("https://example.com", [], [])

    # Assert the result matches our expectation
    assert {:ok, %{status: 200, body: %{"message" => "Test successful"}}} = result
  end
end
