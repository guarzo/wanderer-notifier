defmodule WandererNotifier.Shared.Utils.ValidationManagerTest do
  @moduledoc """
  Tests for the ValidationManager GenServer.
  """

  use ExUnit.Case, async: true

  alias WandererNotifier.Shared.Utils.ValidationManager, as: Manager

  setup do
    # Start a ValidationManager for each test
    {:ok, pid} = GenServer.start_link(Manager, %{})
    %{manager: pid}
  end

  describe "enable_validation/1" do
    test "enables system validation mode", %{manager: manager} do
      assert {:ok, state} = GenServer.call(manager, {:enable, :system})
      assert state.mode == :system
      assert state.expires_at != nil
      assert state.timer_ref != nil
    end

    test "enables character validation mode", %{manager: manager} do
      assert {:ok, state} = GenServer.call(manager, {:enable, :character})
      assert state.mode == :character
      assert state.expires_at != nil
      assert state.timer_ref != nil
    end
  end

  describe "check_and_consume/0" do
    test "consumes system validation mode", %{manager: manager} do
      GenServer.call(manager, {:enable, :system})
      assert {:ok, :system} = GenServer.call(manager, :check_and_consume)
      # Should be disabled after consumption
      assert {:ok, :disabled} = GenServer.call(manager, :check_and_consume)
    end

    test "consumes character validation mode", %{manager: manager} do
      GenServer.call(manager, {:enable, :character})
      assert {:ok, :character} = GenServer.call(manager, :check_and_consume)
      # Should be disabled after consumption
      assert {:ok, :disabled} = GenServer.call(manager, :check_and_consume)
    end

    test "returns disabled when no validation active", %{manager: manager} do
      assert {:ok, :disabled} = GenServer.call(manager, :check_and_consume)
    end
  end

  describe "get_status/0" do
    test "returns disabled status by default", %{manager: manager} do
      status = GenServer.call(manager, :get_status)
      assert status.mode == :disabled
      assert status.expires_at == nil
    end

    test "returns active status when validation enabled", %{manager: manager} do
      GenServer.call(manager, {:enable, :system})
      status = GenServer.call(manager, :get_status)
      assert status.mode == :system
      assert status.expires_at != nil
    end
  end

  describe "disable_validation/0" do
    test "disables active validation", %{manager: manager} do
      GenServer.call(manager, {:enable, :system})
      assert {:ok, _state} = GenServer.call(manager, :disable)

      status = GenServer.call(manager, :get_status)
      assert status.mode == :disabled
    end
  end
end
