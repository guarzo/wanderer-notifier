defmodule WandererNotifier.Services.CharacterKillsServiceTest do
  use ExUnit.Case, async: false
  import Mock
  alias WandererNotifier.Services.CharacterKillsService
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  # Sample test data
  @sample_character_id 123_456_789
  @sample_tracked_characters [
    %{
      "character_id" => "123456789",
      "character_name" => "Test Character"
    }
  ]

  @sample_zkill_response [
    %{
      "killmail_id" => 12345,
      "zkb" => %{
        "hash" => "abcdef123456",
        "totalValue" => 1_000_000_000
      }
    }
  ]

  @sample_esi_data %{
    "killmail_time" => "2023-01-01T12:00:00Z",
    "solar_system_id" => 30_000_142,
    "victim" => %{
      "character_id" => 987_654_321,
      "character_name" => "Victim Name",
      "ship_type_id" => 123,
      "ship_type_name" => "Ship Name"
    },
    "attackers" => [
      %{
        "character_id" => 123_456_789,
        "character_name" => "Test Character",
        "ship_type_id" => 456,
        "ship_type_name" => "Attacker Ship"
      }
    ]
  }

  @sample_system_info %{
    "name" => "Jita"
  }

  describe "fetch_and_persist_character_kills/3" do
    setup do
      # Clear any stored cached data
      on_exit(fn ->
        nil
        # You can add cleanup here if needed
      end)

      :ok
    end

    test "fetches and processes character kills successfully" do
      with_mocks([
        {WandererNotifier.Api.ZKill.Client, [],
         [
           get_character_kills: fn _, _, _ -> {:ok, @sample_zkill_response} end
         ]},
        {WandererNotifier.Api.ESI.Service, [],
         [
           get_killmail: fn _, _ -> {:ok, @sample_esi_data} end,
           get_system_info: fn _ -> {:ok, @sample_system_info} end
         ]},
        {WandererNotifier.Resources.KillmailPersistence, [],
         [
           maybe_persist_killmail: fn _ -> {:ok, %{id: "mock-id"}} end
         ]},
        {WandererNotifier.Data.Cache.Repository, [],
         [
           exists?: fn _ -> false end,
           set: fn _, _, _ -> :ok end,
           get: fn _ -> nil end
         ]}
      ]) do
        result = CharacterKillsService.fetch_and_persist_character_kills(@sample_character_id)

        assert {:ok, %{processed: 1, persisted: 1}} = result

        # Verify the ZKill client was called with correct params
        assert_called(
          WandererNotifier.Api.ZKill.Client.get_character_kills(@sample_character_id, 25, 1)
        )

        # Verify ESI service was called
        assert_called(WandererNotifier.Api.ESI.Service.get_killmail(12345, "abcdef123456"))

        # Verify persistence was called
        assert_called(WandererNotifier.Resources.KillmailPersistence.maybe_persist_killmail(:_))
      end
    end

    test "handles API error gracefully" do
      with_mocks([
        {WandererNotifier.Api.ZKill.Client, [],
         [
           get_character_kills: fn _, _, _ -> {:error, :api_error} end
         ]},
        {WandererNotifier.Data.Cache.Repository, [],
         [
           exists?: fn _ -> false end,
           set: fn _, _, _ -> :ok end,
           get: fn _ -> nil end
         ]}
      ]) do
        result = CharacterKillsService.fetch_and_persist_character_kills(@sample_character_id)

        assert {:error, :api_error} = result
      end
    end

    test "uses cached data when available" do
      with_mocks([
        {WandererNotifier.Resources.KillmailPersistence, [],
         [
           maybe_persist_killmail: fn _ -> {:ok, %{id: "mock-id"}} end
         ]},
        {WandererNotifier.Data.Cache.Repository, [],
         [
           exists?: fn key ->
             key == "zkill:character_kills:#{@sample_character_id}:1"
           end,
           get: fn key ->
             cond do
               key == "zkill:character_kills:#{@sample_character_id}:1" ->
                 {:ok, @sample_zkill_response}

               key == "esi:killmail:12345" ->
                 @sample_esi_data

               true ->
                 nil
             end
           end,
           set: fn _, _, _ -> :ok end
         ]},
        {WandererNotifier.Api.ESI.Service, [],
         [
           get_killmail: fn _, _ -> {:ok, @sample_esi_data} end,
           get_system_info: fn _ -> {:ok, @sample_system_info} end
         ]},
        {WandererNotifier.Api.ZKill.Client, [],
         [
           get_character_kills: fn _, _, _ -> {:ok, []} end
         ]}
      ]) do
        result = CharacterKillsService.fetch_and_persist_character_kills(@sample_character_id)

        assert {:ok, %{processed: 1, persisted: 1}} = result

        # Verify the ZKill client was NOT called
        assert_not_called(WandererNotifier.Api.ZKill.Client.get_character_kills(:_, :_, :_))
      end
    end
  end

  describe "fetch_and_persist_all_tracked_character_kills/2" do
    test "fetches and processes kills for all tracked characters" do
      with_mocks([
        {WandererNotifier.Helpers.CacheHelpers, [],
         [
           get_tracked_characters: fn -> @sample_tracked_characters end
         ]},
        {WandererNotifier.Data.Cache.Repository, [],
         [
           get: fn _ -> nil end,
           exists?: fn _ -> false end,
           set: fn _, _, _ -> :ok end,
           put: fn _, _ -> :ok end
         ]},
        {WandererNotifier.Api.ZKill.Client, [],
         [
           get_character_kills: fn _, _, _ -> {:ok, @sample_zkill_response} end
         ]},
        {WandererNotifier.Api.ESI.Service, [],
         [
           get_killmail: fn _, _ -> {:ok, @sample_esi_data} end,
           get_system_info: fn _ -> {:ok, @sample_system_info} end
         ]},
        {WandererNotifier.Resources.KillmailPersistence, [],
         [
           maybe_persist_killmail: fn _ -> {:ok, %{id: "mock-id"}} end
         ]}
      ]) do
        result = CharacterKillsService.fetch_and_persist_all_tracked_character_kills()

        assert {:ok, %{processed: 1, persisted: 1, characters: 1}} = result
      end
    end
  end
end
