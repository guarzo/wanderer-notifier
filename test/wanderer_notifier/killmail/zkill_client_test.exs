defmodule WandererNotifier.Killmail.ZKillClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.HTTPMock, as: HttpClientMock
  alias WandererNotifier.Killmail.ZKillClient

  setup :verify_on_exit!

  setup do
    # Set up the HTTP client mock
    Application.put_env(:wanderer_notifier, :http_client, HttpClientMock)
    :ok
  end

  describe "get_single_killmail/1" do
    test "get_single_killmail/1 returns decoded killmail when successful" do
      kill_id = "12345"
      url = "https://zkillboard.com/api/kills/killID/#{kill_id}/"

      headers = [
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"},
        {"Cache-Control", "no-cache"}
      ]

      killmail_data = [
        %{
          "killmail_id" => 12_345,
          "zkb" => %{"hash" => "test_hash"},
          "solar_system_id" => 30_000_142
        }
      ]

      expect(HttpClientMock, :get, fn ^url, ^headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(killmail_data)}}
      end)

      assert {:ok, killmail} = ZKillClient.get_single_killmail(kill_id)
      assert killmail["killmail_id"] == 12_345
      assert killmail["zkb"]["hash"] == "test_hash"
      assert killmail["solar_system_id"] == 30_000_142
    end
  end

  describe "get_recent_kills/1" do
    test "handles API responses" do
      url = "https://zkillboard.com/api/kills/recent/"

      headers = [
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"},
        {"Cache-Control", "no-cache"}
      ]

      # Simulate any valid ZKill API response
      response_data = [%{"error" => "recent is an invalid parameter"}]
      encoded_json = Jason.encode!(response_data)

      expect(HttpClientMock, :get, fn ^url, ^headers, _opts ->
        {:ok, %{status_code: 200, body: encoded_json}}
      end)

      result = ZKillClient.get_recent_kills(1)

      # We can only verify that the implementation returns a valid result
      assert {:ok, kills} = result
      assert is_list(kills)
    end
  end
end
