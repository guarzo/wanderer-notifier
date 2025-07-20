defmodule WandererNotifier.ESI.ClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Infrastructure.Adapters.ESI.Client

  # Module attribute to control mock behavior in error cases
  @moduledoc false

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    Application.put_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HTTPMock
    )

    :ok
  end

  describe "get_killmail/3" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/killmails/123/abc/", _headers, _opts ->
          {:ok, %{status_code: 200, body: %{foo: "bar"}}}
      end)

      assert {:ok, %{foo: "bar"}} = Client.get_killmail(123, "abc")
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.get_killmail(123, "abc")
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_killmail(123, "abc")
    end
  end

  describe "get_character_info/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/characters/123/", _headers, _opts ->
          {:ok, %{status_code: 200, body: %{name: "Test Character"}}}
      end)

      assert {:ok, %{name: "Test Character"}} = Client.get_character_info(123)
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.get_character_info(123)
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_character_info(123)
    end
  end

  describe "get_corporation_info/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/corporations/789/", _headers, _opts ->
          {:ok, %{status_code: 200, body: %{name: "Test Corporation"}}}
      end)

      assert {:ok, %{name: "Test Corporation"}} = Client.get_corporation_info(789)
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.get_corporation_info(789)
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_corporation_info(789)
    end
  end

  describe "get_alliance_info/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/alliances/345/", _headers, _opts ->
          {:ok, %{status_code: 200, body: %{name: "Test Alliance"}}}
      end)

      assert {:ok, %{name: "Test Alliance"}} = Client.get_alliance_info(345)
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.get_alliance_info(345)
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_alliance_info(345)
    end
  end

  describe "get_universe_type/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/universe/types/999/", _headers, _opts ->
          {:ok, %{status_code: 200, body: %{type_name: "Test Type"}}}
      end)

      assert {:ok, %{type_name: "Test Type"}} = Client.get_universe_type(999)
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.get_universe_type(999)
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_universe_type(999)
    end
  end

  describe "search_inventory_type/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/search/?categories=inventory_type&search=test&strict=false",
        _headers,
        _opts ->
          {:ok, %{status_code: 200, body: %{search: "result"}}}
      end)

      assert {:ok, %{search: "result"}} = Client.search_inventory_type("test")
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.search_inventory_type("test")
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.search_inventory_type("test")
    end
  end

  describe "get_system/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/universe/systems/42/?datasource=tranquility",
        [{"Accept", "application/json"}, {"User-Agent", "WandererNotifier/1.0"}],
        _opts ->
          {:ok, %{status_code: 200, body: %{system_name: "Test System"}}}
      end)

      assert {:ok, %{system_name: "Test System"}} = Client.get_system(42)
    end

    test "returns {:error, {:system_not_found, system_id}} on 404 response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/universe/systems/42/?datasource=tranquility",
        [{"Accept", "application/json"}, {"User-Agent", "WandererNotifier/1.0"}],
        _opts ->
          {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, {:system_not_found, 42}} = Client.get_system(42)
    end

    test "returns {:error, {:http_error, status}} on other non-2xx responses" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/universe/systems/42/?datasource=tranquility",
        [{"Accept", "application/json"}, {"User-Agent", "WandererNotifier/1.0"}],
        _opts ->
          {:ok, %{status_code: 500, body: "Internal Server Error"}}
      end)

      assert {:error, {:http_error, 500}} = Client.get_system(42)
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/universe/systems/42/?datasource=tranquility",
        [{"Accept", "application/json"}, {"User-Agent", "WandererNotifier/1.0"}],
        _opts ->
          {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_system(42)
    end
  end

  describe "get_system_kills/2" do
    test "returns {:ok, body} on 2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn
        "https://esi.evetech.net/latest/universe/system_kills/", _headers, _opts ->
          {:ok, %{status_code: 200, body: [%{"system_id" => 1, "kills" => 5}]}}
      end)

      assert {:ok, [%{"system_id" => 1, "kills" => 5}]} = Client.get_system_kills(42)
    end

    test "returns {:error, {:http_error, status}} on non-2xx response" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = Client.get_system_kills(42)
    end

    test "returns {:error, reason} on network error" do
      Mox.expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Client.get_system_kills(42)
    end
  end
end
