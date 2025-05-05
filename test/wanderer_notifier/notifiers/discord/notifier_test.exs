defmodule WandererNotifier.Notifiers.Discord.NotifierTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  alias WandererNotifier.Config.Application
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Notifiers.Discord.Notifier

  setup do
    previous_env = Application.get_env(:wanderer_notifier, :env)
    previous_log_level = Logger.level()

    Application.put_env(:wanderer_notifier, :env, :test)
    Logger.configure(level: :info)

    on_exit(fn ->
      Application.put_env(:wanderer_notifier, :env, previous_env)
      Logger.configure(level: previous_log_level)
    end)

    {:ok, %{previous_env: previous_env, previous_log_level: previous_log_level}}
  end

  describe "send_message/2" do
    test "handles basic message in test mode" do
      # Use a more direct approach to ensure we capture the log
      assert capture_log(fn ->
               assert :ok = Notifier.send_message("Test message")
             end) =~ "DISCORD MOCK: Test message"
    end
  end

  describe "send_embed/4" do
    test "handles basic embed in test mode" do
      # Use a more direct approach to ensure we capture the log
      assert capture_log(fn ->
               assert :ok =
                        Notifier.send_embed(
                          "Test Title",
                          "Test Description",
                          "https://example.com"
                        )
             end) =~ "DISCORD MOCK: Test Title - Test Description"
    end
  end

  describe "Killmail.new usage" do
    test "properly creates a killmail struct from map data" do
      # Test data matching what would be in the notifier
      killmail_id = "12345"
      zkb_data = %{"totalValue" => 1_000_000_000, "points" => 100}

      # Create a killmail using the signature we expect
      killmail = Killmail.new(killmail_id, zkb_data)

      # Validate the struct is properly created
      assert %Killmail{} = killmail
      assert killmail.killmail_id == killmail_id
      assert killmail.zkb == zkb_data
      assert killmail.esi_data == nil
    end

    test "properly handles with three parameters" do
      # Test data matching what would be in the notifier
      killmail_id = "12345"
      zkb_data = %{"totalValue" => 1_000_000_000, "points" => 100}
      esi_data = %{"solar_system_id" => 30_000_142, "victim" => %{"ship_type_id" => 123}}

      # Create a killmail using all three parameters
      killmail = Killmail.new(killmail_id, zkb_data, esi_data)

      # Validate the struct is properly created
      assert %Killmail{} = killmail
      assert killmail.killmail_id == killmail_id
      assert killmail.zkb == zkb_data
      assert killmail.esi_data == esi_data
    end
  end
end
