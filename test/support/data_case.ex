defmodule WandererNotifier.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use WandererNotifier.DataCase, async: true`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias WandererNotifier.Resources.Api

      import WandererNotifier.DataCase
    end
  end

  setup _tags do
    # Mock the Ash API for testing resources
    Mox.stub(WandererNotifier.MockCacheHelpers, :get_character_name, fn character_id ->
      {:ok, "Test Character #{character_id}"}
    end)

    Mox.stub(WandererNotifier.MockRepository, :get_tracked_characters, fn ->
      [
        %{
          character_id: 123_456,
          character_name: "Test Character"
        }
      ]
    end)

    Mox.stub(WandererNotifier.MockLogger, :kill_info, fn _, _ -> :ok end)
    Mox.stub(WandererNotifier.MockLogger, :kill_debug, fn _, _ -> :ok end)
    Mox.stub(WandererNotifier.MockLogger, :kill_error, fn _, _ -> :ok end)
    Mox.stub(WandererNotifier.MockLogger, :kill_warn, fn _, _ -> :ok end)

    # Create a test context
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Helper to create a killmail struct for testing.
  """
  def create_test_killmail(attrs \\ %{}) do
    default_attrs = %{
      killmail_id: 12345,
      zkb: %{
        "totalValue" => 15_000_000,
        "points" => 10,
        "npc" => false,
        "solo" => false,
        "hash" => "abc123hash"
      },
      esi_data: %{
        "killmail_time" => "2023-01-01T12:34:56Z",
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita",
        "victim" => %{
          "character_id" => 98765,
          "character_name" => "Victim Pilot",
          "ship_type_id" => 587,
          "ship_type_name" => "Rifter"
        },
        "attackers" => [
          %{
            "character_id" => 11111,
            "character_name" => "Attacker One",
            "ship_type_id" => 24700,
            "ship_type_name" => "Brutix",
            "final_blow" => true,
            "damage_done" => 500
          }
        ]
      }
    }

    attrs = Map.merge(default_attrs, attrs)

    struct(WandererNotifier.Data.Killmail, attrs)
  end
end
