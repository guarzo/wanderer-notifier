defmodule WandererNotifier.Discord.CommandRegistrarTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Discord.CommandRegistrar

  describe "register/0" do
    setup do
      # Save original value
      original_value = Application.get_env(:wanderer_notifier, :discord_application_id)

      on_exit(fn ->
        # Restore original value after test
        Application.put_env(:wanderer_notifier, :discord_application_id, original_value)
      end)

      {:ok, original_value: original_value}
    end

    test "returns error when DISCORD_APPLICATION_ID is not set", _context do
      # Clear the application ID
      Application.put_env(:wanderer_notifier, :discord_application_id, nil)

      assert {:error, :missing_application_id} = CommandRegistrar.register()
    end
  end

  describe "commands/0" do
    test "returns the command structure" do
      commands = CommandRegistrar.commands()
      assert is_list(commands)
      assert length(commands) == 1

      [notifier_command] = commands
      assert notifier_command.name == "notifier"

      assert notifier_command.description ==
               "WandererNotifier configuration and tracking commands"

      assert is_list(notifier_command.options)
      assert length(notifier_command.options) == 2

      # Check subcommands
      subcommand_names = Enum.map(notifier_command.options, & &1.name)
      assert "system" in subcommand_names
      assert "status" in subcommand_names
    end
  end

  describe "valid_interaction?/1" do
    test "validates correct system command" do
      interaction = %{
        data: %{
          name: "notifier",
          options: [%{name: "system"}]
        }
      }

      assert CommandRegistrar.valid_interaction?(interaction)
    end

    test "validates correct status command" do
      interaction = %{
        data: %{
          name: "notifier",
          options: [%{name: "status"}]
        }
      }

      assert CommandRegistrar.valid_interaction?(interaction)
    end

    test "rejects invalid subcommand" do
      interaction = %{
        data: %{
          name: "notifier",
          options: [%{name: "invalid"}]
        }
      }

      refute CommandRegistrar.valid_interaction?(interaction)
    end

    test "rejects non-notifier command" do
      interaction = %{
        data: %{
          name: "other",
          options: []
        }
      }

      refute CommandRegistrar.valid_interaction?(interaction)
    end
  end
end
