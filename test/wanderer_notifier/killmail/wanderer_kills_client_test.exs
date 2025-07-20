defmodule WandererNotifier.Killmail.WandererKillsClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.HTTPMock, as: HttpClientMock
  alias WandererNotifier.Domains.Killmail.WandererKillsClient

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # Set up the HTTP client mock
    Application.put_env(:wanderer_notifier, :http_client, HttpClientMock)
    :ok
  end

  describe "get_system_kills/2" do
    test "returns list of kills when successful" do
      system_id = 30_000_142

      expected_kills = [
        %{
          "killmail_id" => 12_345,
          "victim" => %{
            "character_name" => "Test Victim",
            "ship_name" => "Rifter"
          },
          "total_value" => 1_000_000,
          "kill_time" => "2021-01-01T00:00:00Z"
        }
      ]

      response_body = %{"kills" => expected_kills}

      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(response_body)}}
      end)

      assert {:ok, kills} = WandererKillsClient.get_system_kills(system_id, 5, 168)
      assert kills == expected_kills
    end

    test "handles error response" do
      system_id = 30_000_142

      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 500, body: "Internal Server Error"}}
      end)

      assert {:error, _reason} = WandererKillsClient.get_system_kills(system_id, 5, 168)
    end

    test "handles malformed JSON" do
      system_id = 30_000_142

      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: "invalid json"}}
      end)

      assert {:error, _reason} = WandererKillsClient.get_system_kills(system_id, 5, 168)
    end
  end

  describe "get_character_kills/2" do
    test "returns list of kills when successful" do
      character_id = 12_345

      expected_kills = [
        %{
          "killmail_id" => 67_890,
          "victim" => %{
            "character_name" => "Another Victim",
            "ship_name" => "Punisher"
          },
          "total_value" => 2_000_000,
          "kill_time" => "2021-01-02T00:00:00Z"
        }
      ]

      response_body = %{"kills" => expected_kills}

      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(response_body)}}
      end)

      assert {:ok, kills} = WandererKillsClient.get_character_kills(character_id, 10, 168)
      assert kills == expected_kills
    end
  end

  describe "get_recent_kills/1" do
    test "returns list of kills when successful" do
      expected_kills = [
        %{
          "killmail_id" => 11_111,
          "victim" => %{
            "character_name" => "Recent Victim",
            "ship_name" => "Catalyst"
          },
          "total_value" => 500_000,
          "kill_time" => "2021-01-03T00:00:00Z"
        }
      ]

      # Test direct list response (without "kills" wrapper)
      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(expected_kills)}}
      end)

      assert {:ok, kills} = WandererKillsClient.get_recent_kills(10, 168)
      assert kills == expected_kills
    end

    test "handles unexpected response format gracefully" do
      HttpClientMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(%{"unexpected" => "format"})}}
      end)

      assert {:ok, []} = WandererKillsClient.get_recent_kills(10, 168)
    end
  end
end
