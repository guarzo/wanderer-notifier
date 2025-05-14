defmodule WandererNotifier.Core.Application.ServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Core.Application.Service
  alias WandererNotifier.Notifications.DiscordNotifierMock
  alias WandererNotifier.MockNotifierFactory, as: NotifierFactory
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.License.Service, as: LicenseService

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
          last_validated: DateTime.utc_now() |> DateTime.to_string()
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

    stub(NotifierFactory, :notify, fn
      :send_discord_embed_to_channel, [_channel_id, _embed] -> :ok
      :send_message, [_message] -> :ok
      _type, _args -> :ok
    end)

    # Stub the missing ESI.ServiceMock.get_system/2 call
    WandererNotifier.Api.ESI.ServiceMock
    |> stub(:get_system, fn _id, _opts -> {:ok, %{"name" => "Test System"}} end)

    :ok
  end

  describe "startup notification" do
    test "sends startup notification successfully" do
      pid =
        case Process.whereis(Service) do
          nil ->
            {:ok, pid} = Service.start_link([])
            pid

          pid ->
            pid
        end

      send(pid, :send_startup_notification)
      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end
end
