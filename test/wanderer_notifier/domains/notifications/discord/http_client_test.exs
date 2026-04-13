defmodule WandererNotifier.Domains.Notifications.Discord.HttpClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias WandererNotifier.Domains.Notifications.Discord.HttpClient

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "send_embed/3 retry on transport errors" do
    test "succeeds on first attempt without retry" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: %{}}}
      end)

      assert {:ok, :sent} = HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "retries on transport error and succeeds" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: %{}}}
      end)

      assert {:ok, :sent} = HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "returns error after exhausting retries on transport errors" do
      WandererNotifier.HTTPMock
      |> expect(:request, 3, fn :post, _url, _body, _headers, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, %Req.TransportError{reason: :timeout}} =
               HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "does not retry on HTTP-level errors" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 500, body: %{"message" => "Internal Server Error"}}}
      end)

      assert {:error, {:discord_api_error, 500}} =
               HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end

    test "does not retry on rate limit responses" do
      WandererNotifier.HTTPMock
      |> expect(:request, 1, fn :post, _url, _body, _headers, _opts ->
        {:ok, %{status_code: 429, body: %{"retry_after" => 1.5}}}
      end)

      assert {:error, {:rate_limited, 1.5}} =
               HttpClient.send_embed("bot-token", "123456", %{title: "Test"})
    end
  end
end
