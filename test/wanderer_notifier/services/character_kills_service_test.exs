defmodule WandererNotifier.Services.CharacterKillsServiceTest do
  use ExUnit.Case, async: true

  import Mox

  alias WandererNotifier.Services.CharacterKillsService
  alias WandererNotifier.MockZKillClient
  alias WandererNotifier.MockESI
  alias WandererNotifier.MockCacheHelpers
  alias WandererNotifier.MockRepository
  alias WandererNotifier.MockKillmailPersistence
  alias WandererNotifier.MockLogger

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up default mock implementations
    stub(MockLogger, :debug, fn _msg -> :ok end)
    stub(MockLogger, :info, fn _msg -> :ok end)
    stub(MockLogger, :warn, fn _msg -> :ok end)
    stub(MockLogger, :error, fn _msg -> :ok end)
    stub(MockLogger, :api_error, fn _msg, _metadata -> :ok end)
    stub(MockLogger, :processor_debug, fn _msg, _metadata -> :ok end)
    stub(MockLogger, :processor_info, fn _msg, _metadata -> :ok end)
    stub(MockLogger, :processor_warn, fn _msg, _metadata -> :ok end)
    stub(MockLogger, :processor_error, fn _msg, _metadata -> :ok end)

    deps = %{
      logger: MockLogger,
      repository: MockRepository,
      esi_service: MockESI,
      persistence: MockKillmailPersistence,
      zkill_client: MockZKillClient,
      cache_helpers: MockCacheHelpers
    }

    {:ok, deps: deps}
  end

  describe "fetch_and_persist_character_kills/3" do
    test "fetches and processes character kills successfully", %{deps: deps} do
      character_id = 123_456
      kill_time = "2024-01-03T12:00:00Z"

      # Mock cache helpers to return no cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok, []}
      end)

      # Mock ZKill client to return kills
      expect(MockZKillClient, :get_character_kills, fn ^character_id, 25, 1 ->
        {:ok,
         [
           %{
             "killmail_id" => 1,
             "killmail_time" => kill_time,
             "victim" => %{
               "character_id" => 789,
               "ship_type_id" => 123
             }
           }
         ]}
      end)

      # Mock ESI responses
      expect(MockESI, :get_character, fn 789 ->
        {:ok, %{"name" => "Test Victim"}}
      end)

      expect(MockESI, :get_type, fn 123 ->
        {:ok, %{"name" => "Test Ship"}}
      end)

      # Mock killmail persistence
      expect(MockKillmailPersistence, :maybe_persist_killmail, fn _killmail ->
        {:ok, :persisted}
      end)

      result = CharacterKillsService.fetch_and_persist_character_kills(character_id, 25, 1, deps)

      assert {:ok, %{persisted: 1, processed: 1}} = result
    end

    test "handles API error gracefully", %{deps: deps} do
      character_id = 123_456

      # Mock cache helpers to return no cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok, []}
      end)

      # Mock ZKill client to return error
      expect(MockZKillClient, :get_character_kills, fn ^character_id, 25, 1 ->
        {:error, :api_error}
      end)

      result = CharacterKillsService.fetch_and_persist_character_kills(character_id, 25, 1, deps)

      assert {:error, :api_error} = result
    end

    test "uses cached data when available", %{deps: deps} do
      character_id = 123_456
      kill_time = "2024-01-03T12:00:00Z"

      # Mock cache helpers to return cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok,
         [
           %{
             "killmail_id" => 1,
             "killmail_time" => kill_time,
             "victim" => %{
               "character_id" => 789,
               "ship_type_id" => 123
             }
           }
         ]}
      end)

      # Mock ESI responses
      expect(MockESI, :get_character, fn 789 ->
        {:ok, %{"name" => "Test Victim"}}
      end)

      expect(MockESI, :get_type, fn 123 ->
        {:ok, %{"name" => "Test Ship"}}
      end)

      # Mock killmail persistence
      expect(MockKillmailPersistence, :maybe_persist_killmail, fn _killmail ->
        {:ok, :persisted}
      end)

      result = CharacterKillsService.fetch_and_persist_character_kills(character_id, 25, 1, deps)

      assert {:ok, %{persisted: 1, processed: 1}} = result
    end
  end

  describe "fetch_and_persist_all_tracked_character_kills/2" do
    test "fetches and processes kills for all tracked characters", %{deps: deps} do
      character_id = 123_456
      kill_time = "2024-01-03T12:00:00Z"

      # Mock repository to return tracked characters
      expect(MockRepository, :get_tracked_characters, fn ->
        [%{character_id: character_id}]
      end)

      # Mock cache helpers to return no cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok, []}
      end)

      # Mock ZKill client to return kills
      expect(MockZKillClient, :get_character_kills, fn ^character_id, 25, 1 ->
        {:ok,
         [
           %{
             "killmail_id" => 1,
             "killmail_time" => kill_time,
             "victim" => %{
               "character_id" => 789,
               "ship_type_id" => 123
             }
           }
         ]}
      end)

      # Mock ESI responses
      expect(MockESI, :get_character, fn 789 ->
        {:ok, %{"name" => "Test Victim"}}
      end)

      expect(MockESI, :get_type, fn 123 ->
        {:ok, %{"name" => "Test Ship"}}
      end)

      # Mock killmail persistence
      expect(MockKillmailPersistence, :maybe_persist_killmail, fn _killmail ->
        {:ok, :persisted}
      end)

      result = CharacterKillsService.fetch_and_persist_all_tracked_character_kills(25, 1, deps)

      assert {:ok, %{characters: 1, persisted: 1, processed: 1}} = result
    end
  end

  describe "get_kills_for_character/2" do
    test "returns kills for a character within date range", %{deps: deps} do
      character_id = 123_456
      from = ~D[2024-01-01]
      to = ~D[2024-01-07]
      kill_time = "2024-01-03T12:00:00Z"

      # Mock cache helpers to return no cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok, []}
      end)

      # Mock ZKill client to return kills
      expect(MockZKillClient, :get_character_kills, fn ^character_id, 25, 1 ->
        {:ok,
         [
           %{
             "killmail_id" => 1,
             "killmail_time" => kill_time,
             "victim" => %{
               "character_id" => 789,
               "ship_type_id" => 123
             }
           }
         ]}
      end)

      # Mock ESI responses
      expect(MockESI, :get_character, fn 789 ->
        {:ok, %{"name" => "Test Victim"}}
      end)

      expect(MockESI, :get_type, fn 123 ->
        {:ok, %{"name" => "Test Ship"}}
      end)

      result =
        CharacterKillsService.get_kills_for_character(character_id, [from: from, to: to], deps)

      assert {:ok,
              [%{id: 1, time: ^kill_time, victim_name: "Test Victim", ship_name: "Test Ship"}]} =
               result
    end

    test "handles error from ZKillboard API", %{deps: deps} do
      character_id = 123_456
      from = ~D[2024-01-01]
      to = ~D[2024-01-07]

      # Mock cache helpers to return no cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok, []}
      end)

      # Mock ZKill client to return error
      expect(MockZKillClient, :get_character_kills, fn ^character_id, 25, 1 ->
        {:error, :api_error}
      end)

      result =
        CharacterKillsService.get_kills_for_character(character_id, [from: from, to: to], deps)

      assert {:error, :api_error} = result
    end

    test "handles error from ESI API", %{deps: deps} do
      character_id = 123_456
      from = ~D[2024-01-01]
      to = ~D[2024-01-07]
      kill_time = "2024-01-03T12:00:00Z"

      # Mock cache helpers to return no cached kills
      expect(MockCacheHelpers, :get_cached_kills, fn ^character_id ->
        {:ok, []}
      end)

      # Mock ZKill client to return kills
      expect(MockZKillClient, :get_character_kills, fn ^character_id, 25, 1 ->
        {:ok,
         [
           %{
             "killmail_id" => 1,
             "killmail_time" => kill_time,
             "victim" => %{
               "character_id" => 789,
               "ship_type_id" => 123
             }
           }
         ]}
      end)

      # Mock ESI responses with error
      expect(MockESI, :get_character, fn 789 ->
        {:error, :api_error}
      end)

      result =
        CharacterKillsService.get_kills_for_character(character_id, [from: from, to: to], deps)

      assert {:error, :api_error} = result
    end
  end
end
