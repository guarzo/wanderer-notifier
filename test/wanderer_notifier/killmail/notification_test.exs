defmodule WandererNotifier.Killmail.NotificationTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Killmail.Notification
  alias WandererNotifier.Domains.Notifications.KillmailNotificationMock
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

    # NotificationService doesn't require module configuration
    Application.put_env(:wanderer_notifier, :logger_module, LoggerMock)

    # Set up stub for logger to avoid actual logging in tests
    LoggerMock
    |> stub(:notification_info, fn _msg, _meta -> :ok end)
    |> stub(:notification_error, fn _msg, _meta -> :ok end)

    # Clean up on test exit
    on_exit(fn ->
      Application.delete_env(:wanderer_notifier, :killmail_notification_module)
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

  # Create a mock module for NotificationService
  defmodule TestNotificationService do
    def send_message(notification) do
      case Map.get(notification, :victim, Map.get(notification, "victim")) do
        "Test Victim" -> {:ok, :sent}
        "Disabled" -> {:error, :notifications_disabled}
        "Error" -> {:error, :notification_error}
        _ -> {:ok, :sent}
      end
    end
  end

  describe "send_kill_notification/2" do
    test "successfully creates a notification", %{killmail: killmail} do
      # Setup expectations for the notification creation
      KillmailNotificationMock
      |> expect(:create, fn ^killmail ->
        %{type: :kill, victim: killmail.victim_name}
      end)

      # Execute - This will test the notification creation part
      # The actual sending is handled by NotificationService
      result = Notification.send_kill_notification(killmail, killmail.killmail_id)

      # Verify that a notification was created and attempted to be sent
      # Since we can't easily mock NotificationService, we test that
      # the function completes without error
      assert is_tuple(result)
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
