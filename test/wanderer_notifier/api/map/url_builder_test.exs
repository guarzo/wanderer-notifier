defmodule WandererNotifier.Api.Map.UrlBuilderTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias WandererNotifier.Api.Map.UrlBuilder

  # Stub the Config module for testing
  defmodule TestConfig do
    def map_url, do: "https://wanderer.example.com/testslug"
    def map_name, do: "testslug"
    def map_token, do: "test-token"
    def map_csrf_token, do: "test-csrf"
  end

  describe "build_url/3" do
    test "builds a valid URL with slug from parameter" do
      result = UrlBuilder.build_url("map/systems", %{}, "customslug")
      assert {:ok, url} = result
      assert url == "https://wanderer.example.com/api/map/systems?slug=customslug"
    end

    test "returns error if base domain cannot be determined" do
      # Mock Config.map_url to return nil
      with_mock(WandererNotifier.Core.Config, [map_url: fn -> nil end]) do
        result = UrlBuilder.build_url("map/systems")
        assert {:error, reason} = result
        assert reason =~ "MAP_URL is required"
      end
    end
  end

  describe "get_auth_headers/0" do
    test "includes authorization header when token is available" do
      headers = UrlBuilder.get_auth_headers()
      assert Enum.any?(headers, fn {name, _} -> name == "Authorization" end)
    end

    test "includes CSRF token when available" do
      headers = UrlBuilder.get_auth_headers()
      assert Enum.any?(headers, fn {name, _} -> name == "x-csrf-token" end)
    end

    test "logs warning when token is not available" do
      # Mock Config.map_token to return nil
      with_mock(WandererNotifier.Core.Config, [map_token: fn -> nil end]) do
        log =
          capture_log(fn ->
            UrlBuilder.get_auth_headers()
          end)

        assert log =~ "Map token is NOT available"
      end
    end
  end
end
