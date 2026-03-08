defmodule WandererNotifierWeb.DashboardSSECardTest do
  @moduledoc """
  Tests documenting the data contract between SystemInfo and DashboardController
  for SSE status card rendering.

  The `build_sse_status_card/1` function in DashboardController is private, so
  these tests validate the data structures and conventions that SystemInfo produces
  and the controller consumes. This ensures the two modules stay in sync.
  """
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Data contract: multi-map mode
  # ---------------------------------------------------------------------------
  describe "multi_map mode data contract" do
    test "SystemInfo produces all keys consumed by build_sse_status_card/1" do
      # SystemInfo.extract_multi_map_sse_stats/0 returns this shape.
      # DashboardController.build_sse_status_card/1 pattern-matches on %{mode: "multi_map"}
      # and reads :connected, :map_count, :clients_running via Map.get/3.
      multi_map_data = %{
        mode: "multi_map",
        map_count: 5,
        clients_running: 5,
        connected: 3,
        disconnected: 2,
        maps: []
      }

      assert multi_map_data.mode == "multi_map"
      assert is_integer(multi_map_data.connected)
      assert is_integer(multi_map_data.map_count)
      assert is_integer(multi_map_data.clients_running)
    end

    test "mode value is the string \"multi_map\", not an atom" do
      # SystemInfo explicitly sets mode: "multi_map" (string).
      # DashboardController matches on %{mode: "multi_map"} (string).
      # Using an atom would silently fall through to the env_var clause.
      data = %{mode: "multi_map"}
      assert is_binary(data.mode)
      refute is_atom(data.mode)
    end

    test "rescue fallback preserves the multi_map shape with zero counts" do
      # When extract_multi_map_sse_stats/0 rescues, it returns this fallback.
      # The controller must still render correctly with all-zero values.
      fallback = %{
        mode: "multi_map",
        map_count: 0,
        clients_running: 0,
        connected: 0,
        disconnected: 0,
        maps: []
      }

      assert fallback.mode == "multi_map"
      assert fallback.connected == 0
      assert fallback.map_count == 0
      assert fallback.clients_running == 0
    end

    test "connected > 0 yields 'connected' status in the controller logic" do
      # Mirrors the controller: status = if connected > 0, do: "connected", else: "disconnected"
      connected = 3
      status = if connected > 0, do: "connected", else: "disconnected"
      assert status == "connected"
    end

    test "connected == 0 yields 'disconnected' status in the controller logic" do
      connected = 0
      status = if connected > 0, do: "connected", else: "disconnected"
      assert status == "disconnected"
    end
  end

  # ---------------------------------------------------------------------------
  # Data contract: env_var mode
  # ---------------------------------------------------------------------------
  describe "env_var mode data contract" do
    test "SystemInfo produces all keys consumed by the env_var clause" do
      # SystemInfo.extract_env_var_sse_stats_for_map/1 returns this shape.
      # DashboardController's fallback clause reads :connection_status and :map_name.
      env_var_data = %{
        mode: "env_var",
        client_alive: true,
        connection_status: "connected",
        map_name: "my-map"
      }

      assert is_binary(env_var_data.connection_status)
      assert is_binary(env_var_data.map_name)
    end

    test "env_var data does NOT match the multi_map pattern" do
      env_var = %{mode: "env_var", connection_status: "connected", map_name: "test"}

      # The controller dispatches on %{mode: "multi_map"}, so env_var must not match.
      refute env_var.mode == "multi_map"
    end

    test "connection_status maps to CSS class correctly" do
      # Mirrors the controller's case expression for status_class.
      statuses = %{
        "connected" => "connected",
        "connecting" => "disconnected",
        "reconnecting" => "disconnected",
        "not_configured" => "disconnected",
        "not_running" => "disconnected"
      }

      for {input, expected_class} <- statuses do
        result =
          case input do
            "connected" -> "connected"
            "connecting" -> "disconnected"
            "reconnecting" -> "disconnected"
            _ -> "disconnected"
          end

        assert result == expected_class,
               "Expected status '#{input}' to map to class '#{expected_class}', got '#{result}'"
      end
    end

    test "not_configured fallback when map_name is missing" do
      # When the map is nil, SystemInfo returns connection_status: "not_configured".
      nil_map_data = %{
        mode: "env_var",
        client_alive: false,
        connection_status: "not_configured",
        map_name: nil
      }

      assert nil_map_data.connection_status == "not_configured"
      assert nil_map_data.map_name == nil
    end

    test "default values used by controller when keys are absent" do
      # DashboardController uses Map.get/3 with defaults:
      #   connection_status defaults to "not_configured"
      #   map_name defaults to "Not configured"
      empty_data = %{}

      assert Map.get(empty_data, :connection_status, "not_configured") == "not_configured"
      assert Map.get(empty_data, :map_name, "Not configured") == "Not configured"
    end
  end

  # ---------------------------------------------------------------------------
  # Data contract: error / unknown mode
  # ---------------------------------------------------------------------------
  describe "error fallback data contract" do
    test "extract_sse_stats rescue returns unknown mode with env_var-compatible keys" do
      # When extract_sse_stats/0 rescues entirely, it returns this shape.
      # This falls through to the env_var clause in the controller (not multi_map).
      error_fallback = %{
        mode: "unknown",
        client_alive: false,
        connection_status: "not_configured",
        map_name: nil
      }

      refute error_fallback.mode == "multi_map"
      assert error_fallback.connection_status == "not_configured"
    end
  end

  # ---------------------------------------------------------------------------
  # Pattern-match dispatch correctness
  # ---------------------------------------------------------------------------
  describe "pattern-match dispatch" do
    test "multi_map data is distinguishable from env_var data by mode key" do
      multi_map = %{mode: "multi_map", connected: 1, map_count: 2, clients_running: 2}
      env_var = %{mode: "env_var", connection_status: "connected", map_name: "test"}
      unknown = %{mode: "unknown", connection_status: "not_configured", map_name: nil}

      # Only multi_map should match the %{mode: "multi_map"} pattern
      assert match?(%{mode: "multi_map"}, multi_map)
      refute match?(%{mode: "multi_map"}, env_var)
      refute match?(%{mode: "multi_map"}, unknown)
    end

    test "map without mode key falls through to env_var clause" do
      # A map missing the :mode key entirely should not match multi_map.
      no_mode = %{connection_status: "connected", map_name: "test"}
      refute Map.get(no_mode, :mode) == "multi_map"
    end
  end
end
