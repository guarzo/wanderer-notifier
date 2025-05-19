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

    # Correctly stub send_message/1 for NotifierFactory
    NotifierFactory
    |> stub(:send_message, fn _notification -> :ok end)

    # Set up Mox for ESI.Service
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)

    # Set up Mox for Deduplication
    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Notifications.MockDeduplication
    )

    # Set up default stubs
    WandererNotifier.ESI.ServiceMock
    |> stub(:get_character_info, fn id, _opts ->
      case id do
        100 -> {:ok, %{"name" => "Victim", "corporation_id" => 300, "alliance_id" => 400}}
        101 -> {:ok, %{"name" => "Attacker", "corporation_id" => 301, "alliance_id" => 401}}
        _ -> {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}
      end
    end)
    |> stub(:get_corporation_info, fn id, _opts ->
      case id do
        300 -> {:ok, %{"name" => "Victim Corp", "ticker" => "VC"}}
        301 -> {:ok, %{"name" => "Attacker Corp", "ticker" => "AC"}}
        _ -> {:ok, %{"name" => "Unknown Corp", "ticker" => "UC"}}
      end
    end)
    |> stub(:get_alliance_info, fn id, _opts ->
      case id do
        400 -> {:ok, %{"name" => "Victim Alliance", "ticker" => "VA"}}
        401 -> {:ok, %{"name" => "Attacker Alliance", "ticker" => "AA"}}
        _ -> {:ok, %{"name" => "Unknown Alliance", "ticker" => "UA"}}
      end
    end)
    |> stub(:get_type_info, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)
    |> stub(:get_system, fn id, _opts ->
      case id do
        30_000_142 ->
          {:ok,
           %{
             "name" => "Test System",
             "system_id" => 30_000_142,
             "constellation_id" => 20_000_020,
             "security_status" => 0.9,
             "security_class" => "B"
           }}

        _ ->
          {:error, :not_found}
      end
    end)

    # Set up deduplication mock
    WandererNotifier.Notifications.MockDeduplication
    |> stub(:check, fn :kill, _id -> {:ok, :new} end)

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
