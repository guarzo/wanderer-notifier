# Now define the test module
defmodule WandererNotifier.Notifications.Determiner.KillTest do
  use ExUnit.Case, async: true
  import Mox

  # Set up Mox for this test
  alias WandererNotifier.Notifications.Determiner.Kill
  setup(:set_mox_from_context)

  setup :verify_on_exit!

  setup do
    # Set up application environment
    Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.MockSystem)
    Application.put_env(:wanderer_notifier, :character_module, WandererNotifier.MockCharacter)

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.MockDeduplication
    )

    Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)
    Application.put_env(:wanderer_notifier, :dispatcher_module, WandererNotifier.MockDispatcher)

    # Set up default mock responses
    WandererNotifier.MockSystem
    |> stub(:is_tracked?, fn _id -> false end)

    WandererNotifier.MockCharacter
    |> stub(:is_tracked?, fn _id -> false end)

    :ok
  end

  describe "should_notify?/1" do
    test "returns true for tracked system with notifications enabled" do
      killmail = %{
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{"hash" => "hash12345"}
      }

      # Add deduplication mock
      WandererNotifier.MockDeduplication
      |> expect(:check, fn :kill, _ -> {:ok, :new} end)

      WandererNotifier.MockConfig
      |> expect(:get_config, fn ->
        %{
          notifications: %{
            enabled: true,
            kill: %{
              enabled: true,
              system: %{
                enabled: true
              },
              character: %{
                enabled: true
              }
            }
          }
        }
      end)

      WandererNotifier.MockSystem
      |> expect(:is_tracked?, fn 30_000_142 -> true end)

      WandererNotifier.MockCharacter
      |> expect(:is_tracked?, fn 93_345_033 -> false end)

      assert {:ok, %{should_notify: true}} = Kill.should_notify?(killmail)
    end

    test "returns false with reason when notifications are disabled" do
      killmail = %{
        "killmail_id" => 12_345,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033
        }
      }

      # Add deduplication mock
      WandererNotifier.MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      WandererNotifier.MockSystem
      |> expect(:is_tracked?, fn 30_000_142 -> false end)

      WandererNotifier.MockCharacter
      |> expect(:is_tracked?, fn 93_345_033 -> false end)

      assert {:error, :notifications_disabled} =
               Kill.should_notify?(%{
                 killmail: killmail,
                 config: %{
                   notifications: %{
                     enabled: false,
                     kill: %{
                       enabled: true,
                       system: %{
                         enabled: true
                       },
                       character: %{
                         enabled: true
                       }
                     }
                   }
                 }
               })
    end

    test "returns false with reason when kill notifications are disabled" do
      killmail = %{
        "killmail_id" => 12_345,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033
        }
      }

      # Add deduplication mock
      WandererNotifier.MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      WandererNotifier.MockSystem
      |> expect(:is_tracked?, fn 30_000_142 -> false end)

      WandererNotifier.MockCharacter
      |> expect(:is_tracked?, fn 93_345_033 -> false end)

      assert {:error, :kill_notifications_disabled} =
               Kill.should_notify?(%{
                 killmail: killmail,
                 config: %{
                   notifications: %{
                     enabled: true,
                     kill: %{
                       enabled: false,
                       system: %{
                         enabled: true
                       },
                       character: %{
                         enabled: true
                       }
                     }
                   }
                 }
               })
    end

    test "returns false with reason when system notifications are disabled" do
      killmail = %{
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{"hash" => "hash12345"}
      }

      # Add deduplication mock
      WandererNotifier.MockDeduplication
      |> expect(:check, fn :kill, _ -> {:ok, :new} end)

      WandererNotifier.MockSystem
      |> expect(:is_tracked?, fn 30_000_142 -> true end)

      WandererNotifier.MockCharacter
      |> expect(:is_tracked?, fn 93_345_033 -> false end)

      WandererNotifier.MockConfig
      |> expect(:get_config, fn ->
        %{
          notifications: %{
            enabled: true,
            kill: %{
              enabled: true,
              system: %{
                enabled: false
              },
              character: %{
                enabled: true
              }
            }
          }
        }
      end)

      assert {:ok, %{should_notify: false, reason: "System notifications disabled"}} =
               Kill.should_notify?(killmail)
    end

    test "returns false with reason when character notifications are disabled" do
      killmail = %{
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{"hash" => "hash12345"}
      }

      # Add deduplication mock
      WandererNotifier.MockDeduplication
      |> expect(:check, fn :kill, _ -> {:ok, :new} end)

      WandererNotifier.MockSystem
      |> expect(:is_tracked?, fn 30_000_142 -> false end)

      WandererNotifier.MockCharacter
      |> expect(:is_tracked?, fn 93_345_033 -> true end)

      WandererNotifier.MockConfig
      |> expect(:get_config, fn ->
        %{
          notifications: %{
            enabled: true,
            kill: %{
              enabled: true,
              system: %{
                enabled: true
              },
              character: %{
                enabled: false
              }
            }
          }
        }
      end)

      assert {:ok, %{should_notify: false, reason: "Character notifications disabled"}} =
               Kill.should_notify?(killmail)
    end

    test "returns false with reason when no tracked entities" do
      killmail = %{
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{"hash" => "hash12345"}
      }

      # Add deduplication mock
      WandererNotifier.MockDeduplication
      |> expect(:check, fn :kill, _ -> {:ok, :new} end)

      WandererNotifier.MockSystem
      |> expect(:is_tracked?, fn 30_000_142 -> false end)

      WandererNotifier.MockCharacter
      |> expect(:is_tracked?, fn 93_345_033 -> false end)

      WandererNotifier.MockConfig
      |> expect(:get_config, fn ->
        %{
          notifications: %{
            enabled: true,
            kill: %{
              enabled: true,
              system: %{
                enabled: true
              },
              character: %{
                enabled: true
              }
            }
          }
        }
      end)

      assert {:ok, %{should_notify: false, reason: :no_tracked_entities}} =
               Kill.should_notify?(killmail)
    end
  end
end
