defmodule WandererNotifier.Killmail.NotificationTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Killmail.Notification
  alias WandererNotifier.Domains.Notifications.KillmailNotificationMock
  alias WandererNotifier.Domains.Notifications.DispatcherMock
  alias WandererNotifier.Shared.Logger.LoggerMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up test killmail for reuse in tests
    test_killmail = %Killmail{
      killmail_id: "12345",
      victim_name: "Test Victim",
      victim_corporation: "Test Victim Corp",
      victim_corp_ticker: "TVC",
      ship_name: "Test Ship",
      system_name: "Test System",
      attackers: [
        [
          character_name: "Test Attacker",
          corporation_name: "Test Attacker Corp",
          corporation_ticker: "TAC"
        ]
      ],
      zkb: [
        totalValue: 1_000_000,
        points: 10
      ]
    }

    # Set application env to use our mocks for dependency injection
    Application.put_env(
      :wanderer_notifier,
      :killmail_notification_module,
      KillmailNotificationMock
    )

    Application.put_env(:wanderer_notifier, :dispatcher_module, DispatcherMock)
    Application.put_env(:wanderer_notifier, :logger_module, LoggerMock)

    # Set up stub for logger to avoid actual logging in tests
    LoggerMock
    |> stub(:notification_info, fn _msg, _meta -> :ok end)
    |> stub(:notification_error, fn _msg, _meta -> :ok end)

    # Clean up on test exit
    on_exit(fn ->
      Application.delete_env(:wanderer_notifier, :killmail_notification_module)
      Application.delete_env(:wanderer_notifier, :dispatcher_module)
      Application.delete_env(:wanderer_notifier, :logger_module)
    end)

    {:ok, %{killmail: test_killmail}}
  end

  # Test helper modules
  defmodule TestKillmailNotification do
    def create(killmail) do
      # Return a notification object that won't fail with missing fields
      case killmail.killmail_id do
        "error" ->
          raise "Test exception"

        _ ->
          %{
            type: :kill,
            victim: killmail.victim_name,
            data: %{
              victim_name: killmail.victim_name,
              system_name: killmail.system_name
            }
          }
      end
    end
  end

  defmodule TestDispatcher do
    def send_message(notification) do
      case notification.victim do
        "Test Victim" -> {:ok, :sent}
        "Disabled" -> {:error, :notifications_disabled}
        "Error" -> {:error, :notification_error}
      end
    end
  end

  describe "send_kill_notification/2" do
    test "successfully sends a notification", %{killmail: killmail} do
      # Setup expectations for the mocks
      KillmailNotificationMock
      |> expect(:create, fn ^killmail ->
        %{type: :kill, victim: killmail.victim_name}
      end)

      DispatcherMock
      |> expect(:send_message, fn notification ->
        assert notification.victim == "Test Victim"
        {:ok, :sent}
      end)

      # Execute
      result = Notification.send_kill_notification(killmail, killmail.killmail_id)

      # Verify
      assert {:ok, _notification} = result
    end

    test "handles disabled notifications", %{killmail: killmail} do
      # Setup expectations
      KillmailNotificationMock
      |> expect(:create, fn ^killmail ->
        %{type: :kill, victim: "Disabled"}
      end)

      DispatcherMock
      |> expect(:send_message, fn _notification ->
        {:error, :notifications_disabled}
      end)

      # Execute
      result = Notification.send_kill_notification(killmail, killmail.killmail_id)

      # Verify
      assert {:ok, :disabled} = result
    end

    test "handles notification dispatch errors", %{killmail: killmail} do
      # Setup expectations
      KillmailNotificationMock
      |> expect(:create, fn ^killmail ->
        %{type: :kill, victim: "Error"}
      end)

      DispatcherMock
      |> expect(:send_message, fn _notification ->
        {:error, :notification_error}
      end)

      # Execute
      result = Notification.send_kill_notification(killmail, killmail.killmail_id)

      # Verify
      assert {:error, :notification_error} = result
    end

    test "handles exceptions during notification creation", %{killmail: killmail} do
      # Update killmail to trigger exception
      error_killmail = %{killmail | killmail_id: "error"}

      # Setup expectations
      KillmailNotificationMock
      |> expect(:create, fn ^error_killmail ->
        raise "Test exception"
      end)

      # Execute
      result = Notification.send_kill_notification(error_killmail, error_killmail.killmail_id)

      # Verify
      assert {:error, :notification_failed} = result
    end
  end
end
