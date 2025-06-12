defmodule WandererNotifier.Core.Application.ServiceTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Core.Application.Service
  alias WandererNotifier.Notifications.DiscordNotifierMock
  alias WandererNotifier.MockNotifierFactory, as: NotifierFactory
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.License.Service, as: LicenseService
  alias WandererNotifier.MockSystem
  alias WandererNotifier.MockCharacter
  alias WandererNotifier.MockConfig
  alias WandererNotifier.MockDispatcher
  alias WandererNotifier.Utils.TimeUtils

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # Ensure Stats GenServer is started
    case Process.whereis(Stats) do
      nil ->
        # Initialize test state for Stats
        {:ok, _pid} = GenServer.start_link(Stats, [], name: Stats)

      _ ->
        :ok
    end

    # Ensure License Service is started with a valid mock response
    case Process.whereis(LicenseService) do
      nil ->
        # Mock validate response
        mock_response = %{
          valid: true,
          bot_assigned: true,
          details: %{},
          error: nil,
          error_message: nil,
          last_validated: TimeUtils.log_timestamp()
        }

        # Start the license service with mock state
        {:ok, _pid} = GenServer.start_link(LicenseService, mock_response, name: LicenseService)

      _ ->
        :ok
    end

    # Mock DiscordNotifier
    DiscordNotifierMock
    |> stub(:send_kill_notification, fn _killmail, _type, _options -> :ok end)
    |> stub(:send_discord_embed, fn _embed -> :ok end)

    # Correctly stub send_message/1 for NotifierFactory
    NotifierFactory
    |> stub(:send_message, fn _notification -> :ok end)

    # Set up Mox for ESI.Service
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)

    # Set up Mox for Deduplication
    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.MockDeduplication
    )

    # Set up application environment
    Application.put_env(:wanderer_notifier, :system_module, MockSystem)
    Application.put_env(:wanderer_notifier, :character_module, MockCharacter)
    Application.put_env(:wanderer_notifier, :config_module, MockConfig)
    Application.put_env(:wanderer_notifier, :dispatcher_module, MockDispatcher)

    # Set up default mock responses
    MockConfig
    |> stub(:get_config, fn ->
      %{
        notifications: %{
          enabled: true,
          kill: %{
            enabled: true,
            system: %{enabled: true},
            character: %{enabled: true}
          }
        }
      }
    end)

    :ok
  end

  describe "startup notification" do
    test "sends startup notification successfully" do
      # Stop the service if it's already running
      if pid = Process.whereis(Service) do
        Process.exit(pid, :normal)
        # Give it time to fully stop
        :timer.sleep(100)
      end

      # Set up the mock expectation before starting the service
      MockDispatcher
      |> stub(:send_message, fn message ->
        assert message =~ "Wanderer Notifier"
        :ok
      end)

      # Start the service and handle both success and already_started cases
      case Service.start_link([]) do
        {:ok, pid} ->
          assert Process.alive?(pid)
          # Give it time to send the startup message
          :timer.sleep(100)

        {:error, {:already_started, pid}} ->
          assert Process.alive?(pid)
          # Give it time to send the startup message
          :timer.sleep(100)
      end
    end
  end
end
