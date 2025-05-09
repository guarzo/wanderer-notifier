defmodule WandererNotifier.Core.Application.ServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Core.Application.Service
  alias WandererNotifier.Notifications.DiscordNotifierMock
  alias WandererNotifier.MockNotifierFactory, as: NotifierFactory

  setup :verify_on_exit!

  setup do
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
