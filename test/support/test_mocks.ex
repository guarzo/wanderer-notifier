defmodule WandererNotifier.TestMocks do
  @moduledoc """
  Defines and sets up Mox mocks for test dependencies.
  Provides utility functions for configuring standard mock behavior.
  """
  import Mox

  # Define the mocks
  Mox.defmock(MockDeduplication, for: WandererNotifier.Test.DeduplicationBehaviour)
  Mox.defmock(MockCharacter, for: WandererNotifier.Test.CharacterBehaviour)
  Mox.defmock(MockSystem, for: WandererNotifier.Test.SystemBehaviour)

  # Set up default mock behavior
  def setup_default_mocks do
    # Default config behavior
    MockConfig
    |> stub(:get_notification_setting, fn :kill, :enabled -> true end)
    |> stub(:get_config, fn ->
      %{
        "tracked_systems" => ["Test System"],
        "tracked_characters" => ["Test Character"],
        "notifications" => %{
          "kill" => %{
            "enabled" => true
          }
        }
      }
    end)

    # Default deduplication behavior
    MockDeduplication
    |> stub(:check, fn :kill, _killmail_id -> {:ok, :new} end)
    |> stub(:clear_key, fn :kill, _killmail_id -> {:ok, :cleared} end)

    # Default character behavior
    MockCharacter
    |> stub(:is_tracked?, fn _id -> false end)

    # Default system behavior
    MockSystem
    |> stub(:is_tracked?, fn _id -> false end)
  end
end
