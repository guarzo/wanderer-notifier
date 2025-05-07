defmodule WandererNotifier.HttpTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "mocks HTTP client successfully" do
    WandererNotifier.MockHTTP
    |> expect(:get, fn _url ->
      {:ok, %{status: 200, body: %{"message" => "Test successful"}, headers: []}}
    end)

    result = WandererNotifier.MockHTTP.get("https://example.com")
    assert {:ok, %{status: 200, body: %{"message" => "Test successful"}}} = result
  end
end
