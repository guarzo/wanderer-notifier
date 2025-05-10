defmodule WandererNotifier.Notifiers.Discord.NotifierTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger
  import Mox

  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Notifiers.Discord.Notifier
  alias WandererNotifier.Logger.LoggerMock
  alias WandererNotifier.Notifiers.Discord.NeoClientMock
  alias WandererNotifier.Notifications.Formatters.KillmailMock
  alias WandererNotifier.Notifications.Formatters.SystemMock
  alias WandererNotifier.Notifications.Formatters.CharacterMock
  alias WandererNotifier.Notifications.Formatters.PlainTextMock
  alias WandererNotifier.Notifications.LicenseLimiterMock
  alias WandererNotifier.Core.StatsMock
  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.ESI.Entities.SolarSystem

  # Make mocks verifiable
  setup :verify_on_exit!

  setup do
    previous_env = Application.get_env(:wanderer_notifier, :env)
    previous_log_level = Logger.level()

    Application.put_env(:wanderer_notifier, :env, :test)
    Logger.configure(level: :info)

    # Set up test data
    test_killmail = %Killmail{
      killmail_id: "12345",
      victim_name: "Test Victim",
      victim_corporation: "Test Corp",
      victim_alliance: "Test Alliance",
      victim_corp_ticker: "TSTC",
      ship_name: "Test Ship",
      system_name: "Test System",
      zkb: %{
        "totalValue" => 1_000_000,
        "points" => 10,
        "hash" => "abc123"
      },
      attackers: [
        %{
          "character_id" => 98765,
          "character_name" => "Test Attacker",
          "corporation_id" => 54321,
          "corporation_name" => "Attacker Corp",
          "ship_type_id" => 12345,
          "ship_name" => "Attacker Ship"
        }
      ]
    }

    test_character = %MapCharacter{
      id: 12345,
      name: "Test Character",
      corporation_id: 54321,
      corporation_name: "Test Corp",
      corporation_ticker: "TSTC",
      alliance_id: 98765,
      alliance_name: "Test Alliance",
      alliance_ticker: "TSTA"
    }

    test_system = %SolarSystem{
      id: 30_000_142,
      name: "Jita",
      security_status: 0.9,
      star_id: 40_000_001,
      constellation_id: 20_000_020,
      region_id: 10_000_002,
      region_name: "The Forge"
    }

    test_embed = %{
      title: "Test Embed",
      description: "Test description",
      color: 0x3498DB,
      fields: [
        %{
          name: "Test Field",
          value: "Test value"
        }
      ]
    }

    # Register mocks
    Application.put_env(:wanderer_notifier, :logger_module, LoggerMock)
    Application.put_env(:wanderer_notifier, :discord_client_module, NeoClientMock)
    Application.put_env(:wanderer_notifier, :killmail_formatter_module, KillmailMock)
    Application.put_env(:wanderer_notifier, :system_formatter_module, SystemMock)
    Application.put_env(:wanderer_notifier, :character_formatter_module, CharacterMock)
    Application.put_env(:wanderer_notifier, :plaintext_formatter_module, PlainTextMock)
    Application.put_env(:wanderer_notifier, :license_limiter_module, LicenseLimiterMock)
    Application.put_env(:wanderer_notifier, :stats_module, StatsMock)

    # Set up stubs for logger
    LoggerMock
    |> stub(:processor_debug, fn _msg, _meta -> :ok end)
    |> stub(:processor_info, fn _msg, _meta -> :ok end)
    |> stub(:processor_warn, fn _msg, _meta -> :ok end)
    |> stub(:processor_error, fn _msg, _meta -> :ok end)

    # Clean up on exit
    on_exit(fn ->
      Application.put_env(:wanderer_notifier, :env, previous_env)
      Logger.configure(level: previous_log_level)
      Application.delete_env(:wanderer_notifier, :logger_module)
      Application.delete_env(:wanderer_notifier, :discord_client_module)
      Application.delete_env(:wanderer_notifier, :killmail_formatter_module)
      Application.delete_env(:wanderer_notifier, :system_formatter_module)
      Application.delete_env(:wanderer_notifier, :character_formatter_module)
      Application.delete_env(:wanderer_notifier, :plaintext_formatter_module)
      Application.delete_env(:wanderer_notifier, :license_limiter_module)
      Application.delete_env(:wanderer_notifier, :stats_module)
    end)

    {:ok,
     %{
       killmail: test_killmail,
       character: test_character,
       system: test_system,
       embed: test_embed
     }}
  end

  describe "send_message/2" do
    test "handles basic message in test mode" do
      assert capture_log(fn ->
               assert :ok = Notifier.send_message("Test message")
             end) =~ "DISCORD MOCK: \"Test message\""
    end

    test "sends a text message in test mode" do
      result = Notifier.send_message("Test message")
      assert result == :ok
    end

    test "sends a text message via client in production mode" do
      # Temporarily change env
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Set up expectations
      NeoClientMock
      |> expect(:send_message, fn message ->
        assert message == "Test message"
        :ok
      end)

      # Execute
      result = Notifier.send_message("Test message")

      # Restore env
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end

    test "sends an embed message via client in production mode" do
      # Temporarily change env
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Set up test embed
      embed = %{
        title: "Test Embed",
        description: "Test description"
      }

      # Set up expectations
      NeoClientMock
      |> expect(:send_embed, fn message ->
        assert message.title == "Test Embed"
        assert message.description == "Test description"
        :ok
      end)

      # Execute
      result = Notifier.send_message(embed)

      # Restore env
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end

    test "handles unknown message type in production mode" do
      # Temporarily change env
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Execute with invalid message type
      result = Notifier.send_message(123)

      # Restore env
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == {:error, :invalid_message_type}
    end
  end

  describe "send_embed/4" do
    test "handles basic embed in test mode" do
      assert capture_log(fn ->
               assert :ok =
                        Notifier.send_embed(
                          "Test Title",
                          "Test Description",
                          "https://example.com"
                        )
             end) =~ "DISCORD MOCK: Test Title - Test Description"
    end

    test "sends an embed in test mode" do
      result =
        Notifier.send_embed("Test Title", "Test Description", "https://example.com", 0xFF0000)

      assert result == :ok
    end

    test "sends an embed via client in production mode" do
      # Temporarily change env
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Set up expectations
      NeoClientMock
      |> expect(:send_embed, fn embed ->
        assert embed["title"] == "Test Title"
        assert embed["description"] == "Test Description"
        assert embed["url"] == "https://example.com"
        assert embed["color"] == 0xFF0000
        :ok
      end)

      # Execute
      result =
        Notifier.send_embed("Test Title", "Test Description", "https://example.com", 0xFF0000)

      # Restore env
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end
  end

  describe "Killmail.new usage" do
    test "properly creates a killmail struct from map data" do
      killmail_id = "12345"
      zkb_data = %{"totalValue" => 1_000_000_000, "points" => 100}

      killmail = Killmail.new(killmail_id, zkb_data)

      assert %Killmail{} = killmail
      assert killmail.killmail_id == killmail_id
      assert killmail.zkb == zkb_data
      assert killmail.esi_data == nil
    end

    test "properly handles with three parameters" do
      killmail_id = "12345"
      zkb_data = %{"totalValue" => 1_000_000_000, "points" => 100}
      esi_data = %{"solar_system_id" => 30_000_142, "victim" => %{"ship_type_id" => 123}}

      killmail = Killmail.new(killmail_id, zkb_data, esi_data)

      assert %Killmail{} = killmail
      assert killmail.killmail_id == killmail_id
      assert killmail.zkb == zkb_data
      assert killmail.esi_data == esi_data
    end
  end

  describe "send_file/5" do
    test "sends a file in test mode" do
      result = Notifier.send_file("test.txt", "file content", "Test Title", "Test Description")
      assert result == :ok
    end

    test "sends a file via client in production mode" do
      # Temporarily change env
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Set up expectations
      NeoClientMock
      |> expect(:send_file, fn filename, content, title, description ->
        assert filename == "test.txt"
        assert content == "file content"
        assert title == "Test Title"
        assert description == "Test Description"
        :ok
      end)

      # Execute
      result = Notifier.send_file("test.txt", "file content", "Test Title", "Test Description")

      # Restore env
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end
  end

  describe "send_image_embed/5" do
    test "sends an image embed in test mode" do
      result =
        Notifier.send_image_embed(
          "Test Title",
          "Test Description",
          "https://example.com/image.png",
          0xFF0000
        )

      assert result == :ok
    end

    test "sends an image embed via client in production mode" do
      # Temporarily change env
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Set up expectations
      NeoClientMock
      |> expect(:send_embed, fn embed ->
        assert embed["title"] == "Test Title"
        assert embed["description"] == "Test Description"
        assert embed["color"] == 0xFF0000
        assert embed["image"]["url"] == "https://example.com/image.png"
        :ok
      end)

      # Execute
      result =
        Notifier.send_image_embed(
          "Test Title",
          "Test Description",
          "https://example.com/image.png",
          0xFF0000
        )

      # Restore env
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end
  end

  describe "send_enriched_kill_embed/2" do
    test "sends an enriched kill embed with system name", %{killmail: killmail} do
      # Set up expectations for formatter
      KillmailMock
      |> expect(:format_kill_notification, fn km ->
        assert km.killmail_id == killmail.killmail_id
        assert km.system_name == killmail.system_name

        %{
          title: "Test Kill Notification",
          description: "#{km.victim_name} lost a #{km.ship_name} in #{km.system_name}",
          color: 0xFF0000
        }
      end)

      # Execute in test mode
      result = Notifier.send_enriched_kill_embed(killmail, killmail.killmail_id)

      # Verify
      assert result == :ok
    end

    test "adds components when enabled", %{killmail: killmail} do
      # Enable components feature flag
      defmodule MockFeatureFlags do
        def components_enabled?, do: true
      end

      Application.put_env(:wanderer_notifier, :feature_flags_module, MockFeatureFlags)

      # Set up expectations for formatter
      KillmailMock
      |> expect(:format_kill_notification, fn km ->
        assert km.killmail_id == killmail.killmail_id

        %{
          title: "Test Kill Notification",
          description: "Test description",
          color: 0xFF0000
        }
      end)

      # Execute in test mode
      result = Notifier.send_enriched_kill_embed(killmail, killmail.killmail_id)

      # Clean up
      Application.delete_env(:wanderer_notifier, :feature_flags_module)

      # Verify
      assert result == :ok
    end
  end

  describe "send_kill_notification/1" do
    test "sends rich kill notification when allowed", %{killmail: killmail} do
      # Set up expectations
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :killmail -> true end)
      |> expect(:increment, fn :killmail -> :ok end)

      # Set up expectations for sending the enriched kill
      KillmailMock
      |> expect(:format_kill_notification, fn _ ->
        %{
          title: "Test Kill Notification",
          description: "Test description",
          color: 0xFF0000
        }
      end)

      # Execute
      result = Notifier.send_kill_notification(killmail)

      # Verify
      assert result == :ok
    end

    test "sends plain text kill notification when rich not allowed", %{killmail: killmail} do
      # Set up expectations
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :killmail -> false end)

      PlainTextMock
      |> expect(:plain_killmail_notification, fn _ ->
        "Plain text kill notification for #{killmail.victim_name}"
      end)

      NeoClientMock
      |> expect(:send_message, fn message ->
        assert String.contains?(message, "Plain text kill notification")
        :ok
      end)

      # Execute with production mode for client call
      Application.put_env(:wanderer_notifier, :env, :prod)
      result = Notifier.send_kill_notification(killmail)
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end

    test "handles errors gracefully", %{killmail: killmail} do
      # Set up expectations to raise an error
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :killmail -> raise "Test error" end)

      # Execute
      result = Notifier.send_kill_notification(killmail)

      # Verify
      assert {:error, _} = result
    end
  end

  describe "send_new_tracked_character_notification/1" do
    test "sends rich character notification when allowed", %{character: character} do
      # Set up expectations
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :character -> true end)
      |> expect(:increment, fn :character -> :ok end)

      CharacterMock
      |> expect(:format_character_notification, fn char ->
        assert char.id == character.id
        assert char.name == character.name

        %{
          title: "New Character Tracked",
          description: "#{char.name} has been added to tracking",
          color: 0x3498DB
        }
      end)

      StatsMock
      |> expect(:increment, fn :characters -> :ok end)

      # Execute
      result = Notifier.send_new_tracked_character_notification(character)

      # Verify
      assert result == :ok
    end

    test "sends plain text character notification when rich not allowed", %{character: character} do
      # Set up expectations
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :character -> false end)

      PlainTextMock
      |> expect(:plain_character_notification, fn char ->
        "Plain text notification for character #{char.name}"
      end)

      NeoClientMock
      |> expect(:send_message, fn message ->
        assert String.contains?(message, "Plain text notification for character")
        :ok
      end)

      StatsMock
      |> expect(:increment, fn :characters -> :ok end)

      # Execute with production mode for client call
      Application.put_env(:wanderer_notifier, :env, :prod)
      result = Notifier.send_new_tracked_character_notification(character)
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert result == :ok
    end

    test "handles errors gracefully", %{character: character} do
      # Set up expectations to raise an error
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :character -> raise "Test error" end)

      # Execute
      result = Notifier.send_new_tracked_character_notification(character)

      # Verify
      assert {:error, _} = result
    end
  end

  describe "send_new_system_notification/1" do
    test "sends rich system notification when allowed", %{system: system} do
      # Set up expectations
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :system -> true end)
      |> expect(:increment, fn :system -> :ok end)

      SystemMock
      |> expect(:format_system_notification, fn sys ->
        assert sys.id == system.id
        assert sys.name == system.name

        %{
          title: "New System Tracked",
          description: "#{sys.name} has been added to tracking",
          color: 0x3498DB
        }
      end)

      StatsMock
      |> expect(:increment, fn :systems -> :ok end)

      # Execute
      result = Notifier.send_new_system_notification(system)

      # Verify
      assert {:ok, :sent} = result
    end

    test "sends plain text system notification when rich not allowed", %{system: system} do
      # Set up expectations
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :system -> false end)

      PlainTextMock
      |> expect(:plain_system_notification, fn sys ->
        "Plain text notification for system #{sys.name}"
      end)

      NeoClientMock
      |> expect(:send_message, fn message ->
        assert String.contains?(message, "Plain text notification for system")
        :ok
      end)

      StatsMock
      |> expect(:increment, fn :systems -> :ok end)

      # Execute with production mode for client call
      Application.put_env(:wanderer_notifier, :env, :prod)
      result = Notifier.send_new_system_notification(system)
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert {:ok, :sent} = result
    end

    test "handles errors gracefully", %{system: system} do
      # Set up expectations to raise an error
      LicenseLimiterMock
      |> expect(:should_send_rich?, fn :system -> raise "Test error" end)

      # Execute
      result = Notifier.send_new_system_notification(system)

      # Verify
      assert {:error, _} = result
    end
  end

  describe "send_notification/2" do
    test "sends embed notification" do
      # Set up embed
      embed = %{
        title: "Test Embed",
        description: "Test description",
        color: 0x3498DB
      }

      # Set up expectations for production mode
      NeoClientMock
      |> expect(:send_embed, fn e, channel_id ->
        assert e == embed
        assert channel_id == nil
        :ok
      end)

      # Execute with production mode
      Application.put_env(:wanderer_notifier, :env, :prod)
      result = Notifier.send_notification(:send_discord_embed, [embed])
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert {:ok, :sent} = result
    end

    test "sends embed to specific channel" do
      # Set up embed
      embed = %{
        title: "Test Embed",
        description: "Test description",
        color: 0x3498DB
      }

      # Set up expectations for production mode
      NeoClientMock
      |> expect(:send_embed, fn e, channel_id ->
        assert e == embed
        assert channel_id == "12345"
        :ok
      end)

      # Execute with production mode
      Application.put_env(:wanderer_notifier, :env, :prod)
      result = Notifier.send_notification(:send_discord_embed_to_channel, ["12345", embed])
      Application.put_env(:wanderer_notifier, :env, :test)

      # Verify
      assert {:ok, :sent} = result
    end

    test "sends message notification" do
      # Set up expectations for test mode
      result = Notifier.send_notification(:send_message, ["Test message"])

      # Verify
      assert result == :ok
    end

    test "handles unknown notification type" do
      # Execute
      result = Notifier.send_notification(:unknown_type, ["Test data"])

      # Verify
      assert result == {:error, :unsupported_notification_type}
    end
  end
end
