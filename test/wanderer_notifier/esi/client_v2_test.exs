defmodule WandererNotifier.ESI.ClientV2Test do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.ESI.ClientV2

  setup :verify_on_exit!

  describe "ClientV2 basic functionality" do
    test "get_character_info uses new base client" do
      character_id = 123_456

      expected_response = %{
        "name" => "Test Character",
        "corporation_id" => 789_012
      }

      expect(WandererNotifier.HTTPMock, :get, fn url, headers, opts ->
        assert url == "https://esi.evetech.net/latest/characters/#{character_id}/"
        assert {"Accept", "application/json"} in headers
        assert opts[:timeout] == 15_000
        assert opts[:retry_options][:max_attempts] == 3
        assert opts[:rate_limit_options][:requests_per_second] == 20

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = ClientV2.get_character_info(character_id)
      assert {:ok, ^expected_response} = result
    end

    test "get_killmail uses timing and handles response" do
      kill_id = 987_654
      hash = "abcdef123456"

      expected_killmail = %{
        "killmail_id" => kill_id,
        "killmail_time" => "2023-01-01T00:00:00Z"
      }

      expect(WandererNotifier.HTTPMock, :get, fn url, headers, opts ->
        assert url == "https://esi.evetech.net/latest/killmails/#{kill_id}/#{hash}/"

        {:ok, %{status_code: 200, body: expected_killmail}}
      end)

      result = ClientV2.get_killmail(kill_id, hash)
      assert {:ok, ^expected_killmail} = result
    end

    test "handles 404 responses with custom handler" do
      alliance_id = 555_555

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      result = ClientV2.get_alliance_info(alliance_id)
      assert {:error, :not_found} = result
    end

    test "get_system handles specific error cases" do
      system_id = 30_000_142

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "System not found"}}
      end)

      result = ClientV2.get_system(system_id)
      assert {:error, {:system_not_found, ^system_id}} = result
    end

    test "search_inventory_type builds correct query params" do
      query = "Rifter"
      strict = true

      expect(WandererNotifier.HTTPMock, :get, fn url, _headers, _opts ->
        assert url =~ "/search/?"
        assert url =~ "categories=inventory_type"
        assert url =~ "search=Rifter"
        assert url =~ "strict=true"

        {:ok, %{status_code: 200, body: %{"inventory_type" => [587]}}}
      end)

      result = ClientV2.search_inventory_type(query, strict)
      assert {:ok, %{"inventory_type" => [587]}} = result
    end
  end

  describe "ClientV2 configuration" do
    test "uses correct base configuration" do
      assert ClientV2.base_url() == "https://esi.evetech.net/latest"
      assert ClientV2.default_timeout() == 15_000
      assert ClientV2.default_recv_timeout() == 15_000
      assert ClientV2.service_name() == "eve_esi"
    end
  end

  describe "ClientV2 error handling" do
    test "handles network errors" do
      corporation_id = 789_012

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      result = ClientV2.get_corporation_info(corporation_id)
      assert {:error, :timeout} = result
    end

    test "handles HTTP errors" do
      type_id = 587

      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 500, body: "Internal Server Error"}}
      end)

      result = ClientV2.get_universe_type(type_id)
      assert {:error, {:http_error, 500}} = result
    end
  end
end
