defmodule WandererNotifier.Application.Services.Application.ServiceTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Application.Services.Application.Service
  alias WandererNotifier.Application.Services.Stats
  alias WandererNotifier.Domains.License.LicenseService
  alias WandererNotifier.MockSystem
  alias WandererNotifier.MockCharacter
  alias WandererNotifier.MockConfig
  alias WandererNotifier.Shared.Utils.TimeUtils

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

    # NotificationService handles message sending directly

    # Set up Mox for ESI.Service
    Application.put_env(
      :wanderer_notifier,
      :esi_service,
      WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
    )

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
    # NotificationService doesn't require module configuration

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
    test "application service starts successfully" do
      # Stop the service if it's already running
      if pid = Process.whereis(Service) do
        Process.exit(pid, :normal)
        # Give it time to fully stop
        :timer.sleep(100)
      end

      # Start the service and handle both success and already_started cases
      case Service.start_link([]) do
        {:ok, pid} ->
          assert Process.alive?(pid)
          # Service should be running
          assert Process.alive?(pid)

        {:error, {:already_started, pid}} ->
          assert Process.alive?(pid)
          # Service was already running, which is fine for this test
          assert Process.alive?(pid)
      end
    end
  end
end
