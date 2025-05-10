defmodule WandererNotifier.Killmail.ZKillClientTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.ZKillClient

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up test data
    test_kill_response = [
      %{
        "killmail_id" => 12345,
        "zkb" => %{
          "hash" => "abc123",
          "totalValue" => 1_000_000.0,
          "points" => 10
        }
      }
    ]

    test_system_kills = [
      %{
        "killmail_id" => 12345,
        "zkb" => %{
          "hash" => "abc123",
          "totalValue" => 1_000_000.0,
          "points" => 10
        }
      },
      %{
        "killmail_id" => 12346,
        "zkb" => %{
          "hash" => "abc124",
          "totalValue" => 2_000_000.0,
          "points" => 20
        }
      }
    ]

    test_character_kills = [
      %{
        "killmail_id" => 23456,
        "zkb" => %{
          "hash" => "def456",
          "totalValue" => 3_000_000.0,
          "points" => 30
        }
      },
      %{
        "killmail_id" => 23457,
        "zkb" => %{
          "hash" => "def457",
          "totalValue" => 4_000_000.0,
          "points" => 40
        }
      },
      %{
        "killmail_id" => 23458,
        "zkb" => %{
          "hash" => "def458",
          "totalValue" => 5_000_000.0,
          "points" => 50
        }
      }
    ]

    # Define a test HTTP client module
    defmodule MockHttpClient do
      @behaviour WandererNotifier.HttpClient.Behaviour

      # Define the callbacks from the behaviour
      @impl true
      def get(url, headers \\ []) do
        send(self(), {:http_get, url, headers})
        get_response(url)
      end

      # Custom method to handle the three-argument version
      def get(url, headers, _options) do
        send(self(), {:http_get, url, headers})
        get_response(url)
      end

      @impl true
      def post(url, body, headers \\ []) do
        send(self(), {:http_post, url, body, headers})
        {:ok, %{status_code: 200, body: "[]"}}
      end

      @impl true
      def post_json(url, body, headers \\ [], options \\ []) do
        send(self(), {:http_post_json, url, body, headers, options})
        {:ok, %{status_code: 200, body: "[]"}}
      end

      @impl true
      def request(method, url, headers \\ [], body \\ nil, opts \\ []) do
        send(self(), {:http_request, method, url, headers, body, opts})
        {:ok, %{status_code: 200, body: "[]"}}
      end

      @impl true
      def handle_response(response) do
        send(self(), {:handle_response, response})
        response
      end

      defp get_response(url) do
        cond do
          String.contains?(url, "/killID/12345/") ->
            {:ok, %{status_code: 200, body: Jason.encode!(test_kill_response)}}

          true ->
            {:ok, %{status_code: 200, body: Jason.encode!(test_character_kills)}}
        end
      end

      defp test_kill_response do
        [
          %{
            "killmail_id" => 12345,
            "zkb" => %{
              "hash" => "abc123",
              "totalValue" => 1_000_000.0,
              "points" => 10
            }
          }
        ]
      end

      defp test_character_kills do
        [
          %{
            "killmail_id" => 23456,
            "zkb" => %{
              "hash" => "def456",
              "totalValue" => 3_000_000.0,
              "points" => 30
            }
          },
          %{
            "killmail_id" => 23457,
            "zkb" => %{
              "hash" => "def457",
              "totalValue" => 4_000_000.0,
              "points" => 40
            }
          },
          %{
            "killmail_id" => 23458,
            "zkb" => %{
              "hash" => "def458",
              "totalValue" => 5_000_000.0,
              "points" => 50
            }
          }
        ]
      end
    end

    # Set up logger module with a module that doesn't perform actual logging
    defmodule NoopLogger do
      def debug(_msg, _meta \\ []), do: :ok
      def info(_msg, _meta \\ []), do: :ok
      def warn(_msg, _meta \\ []), do: :ok
      def error(_msg, _meta \\ []), do: :ok
      def api_debug(_msg, _meta \\ []), do: :ok
      def api_info(_msg, _meta \\ []), do: :ok
      def api_warn(_msg, _meta \\ []), do: :ok
      def api_error(_msg, _meta \\ []), do: :ok
    end

    # Use application to inject mocks
    Application.put_env(:wanderer_notifier, :http_client, MockHttpClient)
    Application.put_env(:wanderer_notifier, :logger_module, NoopLogger)

    # Clean up on test exit
    on_exit(fn ->
      Application.delete_env(:wanderer_notifier, :http_client)
      Application.delete_env(:wanderer_notifier, :logger_module)
    end)

    {:ok,
     %{
       single_kill: test_kill_response,
       system_kills: test_system_kills,
       character_kills: test_character_kills,
       http_client: MockHttpClient
     }}
  end

  describe "get_single_killmail/1" do
    test "successfully retrieves a killmail", %{single_kill: kill, http_client: http} do
      # Override the mock for this specific test
      defmodule SuccessKillHttpClient do
        def get(_url, _headers, _options) do
          {:ok,
           %{
             status_code: 200,
             body:
               Jason.encode!([
                 %{
                   "killmail_id" => 12345,
                   "zkb" => %{
                     "hash" => "abc123",
                     "totalValue" => 1_000_000.0,
                     "points" => 10
                   }
                 }
               ])
           }}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, SuccessKillHttpClient)

      # Execute
      result = ZKillClient.get_single_killmail(12345)

      # Verify
      assert {:ok, received_kill} = result
      assert received_kill["killmail_id"] == 12345
      assert received_kill["zkb"]["hash"] == "abc123"
    end

    test "handles HTTP error" do
      # Override the mock for this specific test
      defmodule NotFoundHttpClient do
        def get(_url, _headers, _options) do
          {:ok, %{status_code: 404, body: "Not Found"}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, NotFoundHttpClient)

      # Execute
      result = ZKillClient.get_single_killmail(12345)

      # Verify
      assert {:error, {:http_error, 404}} = result
    end

    test "handles network error" do
      # Override the mock for this specific test
      defmodule TimeoutHttpClient do
        def get(_url, _headers, _options) do
          {:error, %{reason: :timeout}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, TimeoutHttpClient)

      # Execute
      result = ZKillClient.get_single_killmail(12345)

      # Verify
      assert {:error, %{reason: :timeout}} = result
    end

    test "handles JSON decode error" do
      # Override the mock for this specific test
      defmodule InvalidJsonHttpClient do
        def get(_url, _headers, _options) do
          {:ok, %{status_code: 200, body: "invalid json"}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, InvalidJsonHttpClient)

      # Execute
      result = ZKillClient.get_single_killmail(12345)

      # Verify
      assert {:error, {:json_decode_error, _}} = result
    end

    test "handles empty response" do
      # Override the mock for this specific test
      defmodule EmptyResponseHttpClient do
        def get(_url, _headers, _options) do
          {:ok, %{status_code: 200, body: "[]"}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, EmptyResponseHttpClient)

      # Execute
      result = ZKillClient.get_single_killmail(12345)

      # Verify
      assert {:error, {:domain_error, :zkill, {:not_found, 12345}}} = result
    end
  end

  describe "get_recent_kills/1" do
    test "successfully retrieves recent kills", %{system_kills: kills} do
      # Override the mock for this specific test
      defmodule RecentKillsHttpClient do
        def get(_url, _headers, _options) do
          {:ok,
           %{
             status_code: 200,
             body:
               Jason.encode!([
                 %{
                   "killmail_id" => 12345,
                   "zkb" => %{
                     "hash" => "abc123",
                     "totalValue" => 1_000_000.0,
                     "points" => 10
                   }
                 },
                 %{
                   "killmail_id" => 12346,
                   "zkb" => %{
                     "hash" => "abc124",
                     "totalValue" => 2_000_000.0,
                     "points" => 20
                   }
                 }
               ])
           }}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, RecentKillsHttpClient)

      # Execute
      result = ZKillClient.get_recent_kills(2)

      # Verify
      assert {:ok, received_kills} = result
      assert length(received_kills) == 2
      assert Enum.at(received_kills, 0)["killmail_id"] == 12345
      assert Enum.at(received_kills, 1)["killmail_id"] == 12346
    end

    test "limits the number of kills returned", %{system_kills: kills} do
      # Override the mock for this specific test
      defmodule LimitKillsHttpClient do
        def get(_url, _headers, _options) do
          {:ok,
           %{
             status_code: 200,
             body:
               Jason.encode!([
                 %{
                   "killmail_id" => 12345,
                   "zkb" => %{
                     "hash" => "abc123",
                     "totalValue" => 1_000_000.0,
                     "points" => 10
                   }
                 },
                 %{
                   "killmail_id" => 12346,
                   "zkb" => %{
                     "hash" => "abc124",
                     "totalValue" => 2_000_000.0,
                     "points" => 20
                   }
                 }
               ])
           }}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, LimitKillsHttpClient)

      # Execute
      result = ZKillClient.get_recent_kills(1)

      # Verify
      assert {:ok, received_kills} = result
      assert length(received_kills) == 1
      assert Enum.at(received_kills, 0)["killmail_id"] == 12345
    end

    test "handles HTTP error" do
      # Override the mock for this specific test
      defmodule HttpErrorClient do
        def get(_url, _headers, _options) do
          {:ok, %{status_code: 500, body: "Internal Server Error"}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, HttpErrorClient)

      # Execute
      result = ZKillClient.get_recent_kills()

      # Verify
      assert {:error, {:http_error, 500}} = result
    end

    test "handles network error" do
      # Override the mock for this specific test
      defmodule NetworkErrorClient do
        def get(_url, _headers, _options) do
          {:error, %{reason: :nxdomain}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, NetworkErrorClient)

      # Execute
      result = ZKillClient.get_recent_kills()

      # Verify
      assert {:error, %{reason: :nxdomain}} = result
    end

    test "handles JSON decode error" do
      # Override the mock for this specific test
      defmodule JsonErrorClient do
        def get(_url, _headers, _options) do
          {:ok, %{status_code: 200, body: "{invalid json"}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, JsonErrorClient)

      # Execute
      result = ZKillClient.get_recent_kills()

      # Verify
      assert {:error, {:json_decode_error, _}} = result
    end
  end

  # The system_kills and character_kills endpoints follow the same pattern,
  # so we'll implement a subset of tests for them

  describe "get_system_kills/2" do
    test "successfully retrieves system kills" do
      # Override the mock for this specific test
      defmodule SystemKillsHttpClient do
        def get(_url, _headers, _options) do
          {:ok,
           %{
             status_code: 200,
             body:
               Jason.encode!([
                 %{
                   "killmail_id" => 12345,
                   "zkb" => %{
                     "hash" => "abc123",
                     "totalValue" => 1_000_000.0,
                     "points" => 10
                   }
                 },
                 %{
                   "killmail_id" => 12346,
                   "zkb" => %{
                     "hash" => "abc124",
                     "totalValue" => 2_000_000.0,
                     "points" => 20
                   }
                 }
               ])
           }}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, SystemKillsHttpClient)

      # Execute
      result = ZKillClient.get_system_kills(30_000_142, 2)

      # Verify
      assert {:ok, received_kills} = result
      assert length(received_kills) == 2
      assert Enum.at(received_kills, 0)["killmail_id"] == 12345
      assert Enum.at(received_kills, 1)["killmail_id"] == 12346
    end
  end

  describe "get_character_kills/3" do
    test "successfully retrieves character kills" do
      # Override the mock for this specific test
      defmodule CharacterKillsHttpClient do
        def get(_url, _headers, _options) do
          {:ok,
           %{
             status_code: 200,
             body:
               Jason.encode!([
                 %{
                   "killmail_id" => 23456,
                   "zkb" => %{
                     "hash" => "def456",
                     "totalValue" => 3_000_000.0,
                     "points" => 30
                   }
                 },
                 %{
                   "killmail_id" => 23457,
                   "zkb" => %{
                     "hash" => "def457",
                     "totalValue" => 4_000_000.0,
                     "points" => 40
                   }
                 },
                 %{
                   "killmail_id" => 23458,
                   "zkb" => %{
                     "hash" => "def458",
                     "totalValue" => 5_000_000.0,
                     "points" => 50
                   }
                 }
               ])
           }}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, CharacterKillsHttpClient)

      # Execute
      result = ZKillClient.get_character_kills(12345, nil, 3)

      # Verify
      assert {:ok, received_kills} = result
      assert length(received_kills) == 3
      assert Enum.at(received_kills, 0)["killmail_id"] == 23456
      assert Enum.at(received_kills, 1)["killmail_id"] == 23457
      assert Enum.at(received_kills, 2)["killmail_id"] == 23458
    end

    test "includes date range in the URL when provided" do
      # Set up date range
      date_range = %{
        start: DateTime.from_naive!(~N[2023-01-01 00:00:00], "Etc/UTC"),
        end: DateTime.from_naive!(~N[2023-01-31 23:59:59], "Etc/UTC")
      }

      # Override the mock for this specific test and add assertions for date range
      defmodule DateRangeHttpClient do
        def get(url, _headers, _options) do
          # Assert here that the URL contains expected date range parameters
          assert String.contains?(url, "characterID/12345")
          assert String.contains?(url, "startTime/2023-01-01")
          assert String.contains?(url, "endTime/2023-01-31")

          {:ok, %{status_code: 200, body: "[]"}}
        end
      end

      # Replace the HTTP client temporarily
      Application.put_env(:wanderer_notifier, :http_client, DateRangeHttpClient)

      # Execute
      ZKillClient.get_character_kills(12345, date_range, 5)
    end
  end
end
