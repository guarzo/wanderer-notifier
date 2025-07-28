defmodule WandererNotifier.Domains.Killmail.EnrichmentRecentKillsTest do
  @moduledoc """
  Specific test suite for recent kills functionality to prevent HTTP client regressions.

  This test validates the fixes made to handle:
  - JSON response format from WandererKills API
  - HTTP client body parsing issues  
  - Pattern matching bugs in response handling
  """

  use ExUnit.Case, async: true

  import Mox

  alias WandererNotifier.Domains.Killmail.Enrichment

  setup :verify_on_exit!

  describe "recent_kills_for_system/2" do
    test "handles wrapped API response format correctly" do
      # Mock the exact response format from WandererKills API
      api_response = %{
        "data" => %{
          "timestamp" => "2025-07-28T17:55:00.691766Z",
          "cached" => false,
          "kills" => [
            %{
              "killmail_id" => 128_791_229,
              "zkb" => %{
                "totalValue" => 35_187_361.6,
                "points" => 3,
                "hash" => "079eb9ac475bf7961b9ad90524f1fc1aab58e27b"
              }
            },
            %{
              "killmail_id" => 128_791_224,
              "zkb" => %{
                "totalValue" => 20_670.67,
                "points" => 1,
                "hash" => "bc9e9bc80f52c425b6f900a61bf498b614547d68"
              }
            }
          ]
        },
        "timestamp" => "2025-07-28T17:55:00.691774Z"
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      # Should successfully parse and format kills
      assert is_binary(result)
      assert String.contains?(result, "zkillboard.com/kill/128791229")
      assert String.contains?(result, "zkillboard.com/kill/128791224")
      assert String.contains?(result, "35.2M ISK kill")
      assert String.contains?(result, "20.7K ISK kill")
      assert String.contains?(result, "(3 pts)")
      assert String.contains?(result, "(1 pts)")
    end

    test "handles direct array response format (fallback)" do
      # Mock direct array response (fallback format)
      api_response = [
        %{
          "killmail_id" => 128_001_234,
          "zkb" => %{
            "totalValue" => 150_000_000,
            "points" => 10
          }
        }
      ]

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(30_000_142, 1)

      assert is_binary(result)
      assert String.contains?(result, "zkillboard.com/kill/128001234")
      assert String.contains?(result, "150.0M ISK kill")
      assert String.contains?(result, "(10 pts)")
    end

    test "handles empty kills response correctly" do
      api_response = %{
        "data" => %{
          "kills" => []
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      assert result == "No recent kills found"
    end

    test "handles HTTP errors gracefully" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      assert result == "Error retrieving kill data"
    end

    test "handles non-200 HTTP status codes" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 500, body: "Internal Server Error"}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      assert result == "Error retrieving kill data"
    end

    test "handles invalid JSON response" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: "invalid json {"}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      assert result == "Error retrieving kill data"
    end

    test "handles unexpected response format" do
      # Mock response with unexpected structure
      api_response = %{
        "unexpected" => "format",
        "no_kills" => "here"
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      # Should handle gracefully and return empty result
      assert result == "Error retrieving kill data"
    end

    test "formats ISK values correctly" do
      api_response = %{
        "data" => %{
          "kills" => [
            # 1.5B
            %{"killmail_id" => 1, "zkb" => %{"totalValue" => 1_500_000_000, "points" => 15}},
            # 250M
            %{"killmail_id" => 2, "zkb" => %{"totalValue" => 250_000_000, "points" => 8}},
            # 5.5M
            %{"killmail_id" => 3, "zkb" => %{"totalValue" => 5_500_000, "points" => 3}},
            # 750K
            %{"killmail_id" => 4, "zkb" => %{"totalValue" => 750_000, "points" => 2}},
            # 50K
            %{"killmail_id" => 5, "zkb" => %{"totalValue" => 50_000, "points" => 1}},
            # 999 ISK
            %{"killmail_id" => 6, "zkb" => %{"totalValue" => 999, "points" => 1}}
          ]
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 6)

      # Check ISK formatting
      assert String.contains?(result, "1.5B ISK kill")
      assert String.contains?(result, "250.0M ISK kill")
      assert String.contains?(result, "5.5M ISK kill")
      assert String.contains?(result, "750.0K ISK kill")
      assert String.contains?(result, "50.0K ISK kill")
      assert String.contains?(result, "999 ISK kill")
    end

    test "preserves kill order from API" do
      api_response = %{
        "data" => %{
          "kills" => [
            %{"killmail_id" => 111, "zkb" => %{"totalValue" => 1_000_000, "points" => 1}},
            %{"killmail_id" => 222, "zkb" => %{"totalValue" => 2_000_000, "points" => 2}},
            %{"killmail_id" => 333, "zkb" => %{"totalValue" => 3_000_000, "points" => 3}}
          ]
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)
      lines = String.split(result, "\n")

      # Should preserve order: 111, 222, 333
      assert Enum.at(lines, 0) |> String.contains?("kill/111")
      assert Enum.at(lines, 1) |> String.contains?("kill/222")
      assert Enum.at(lines, 2) |> String.contains?("kill/333")
    end

    test "validates link format in kill output" do
      api_response = %{
        "data" => %{
          "kills" => [
            %{
              "killmail_id" => 128_846_484,
              "zkb" => %{"totalValue" => 138_660_686.78, "points" => 14}
            }
          ]
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(30_000_142, 1)

      # Validate exact link format: [value](url) (points)
      expected_pattern =
        ~r/\[138\.7M ISK kill\]\(https:\/\/zkillboard\.com\/kill\/128846484\/\) \(14 pts\)/

      assert Regex.match?(expected_pattern, result)
    end
  end

  describe "regression prevention" do
    test "prevents body parsing regression (map vs string)" do
      # This test ensures we handle both string and map response bodies correctly
      # The original bug was that Req parsed JSON into maps, but code expected strings

      api_response_map = %{
        "data" => %{
          "kills" => [
            %{"killmail_id" => 123, "zkb" => %{"totalValue" => 1_000_000, "points" => 5}}
          ]
        }
      }

      # Test both potential response body formats
      test_bodies = [
        # Already parsed as map (current Req behavior)
        api_response_map,
        # As JSON string (potential fallback behavior)
        Jason.encode!(api_response_map)
      ]

      for {body_format, index} <- Enum.with_index(test_bodies, 1) do
        expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
          {:ok, %{status_code: 200, body: body_format}}
        end)

        result = Enrichment.recent_kills_for_system(31_001_000, 1)

        assert is_binary(result), "Failed for body format #{index}"

        assert String.contains?(result, "zkillboard.com/kill/123"),
               "Failed for body format #{index}"

        assert String.contains?(result, "1.0M ISK kill"), "Failed for body format #{index}"
      end
    end

    test "prevents HTTP client middleware regression" do
      # Test that the direct Req fallback mechanism works
      # This prevents regression where HTTP client middleware blocks requests

      api_response = %{
        "data" => %{
          "kills" => [
            %{"killmail_id" => 999, "zkb" => %{"totalValue" => 5_000_000, "points" => 7}}
          ]
        }
      }

      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
        # Ensure we're hitting the correct WandererKills API endpoint
        assert String.contains?(url, "/api/v1/kills/system/")
        assert String.contains?(url, "limit=3")
        assert String.contains?(url, "since_hours=168")

        {:ok, %{status_code: 200, body: Jason.encode!(api_response)}}
      end)

      result = Enrichment.recent_kills_for_system(31_001_000, 3)

      assert String.contains?(result, "5.0M ISK kill")
      assert String.contains?(result, "(7 pts)")
    end
  end
end
