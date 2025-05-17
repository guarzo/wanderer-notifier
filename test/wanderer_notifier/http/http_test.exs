defmodule WandererNotifier.HttpTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "mocks HTTP client successfully" do
    WandererNotifier.HttpClient.HttpoisonMock
    |> expect(:get, fn "https://example.com" ->
      {:ok, %{status: 200, body: %{"message" => "Test successful"}, headers: []}}
    end)

    result = WandererNotifier.HttpClient.HttpoisonMock.get("https://example.com")
    assert {:ok, %{status: 200, body: %{"message" => "Test successful"}}} = result
  end
end
