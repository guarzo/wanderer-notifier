defmodule WandererNotifier.Test.Support.Mocks.TestDataFactory do
  @moduledoc """
  Centralized test data factory for WandererNotifier tests.

  This module consolidates all test data creation functions and provides
  a consistent API for generating test data across the test suite.

  Replaces scattered test data functions from:
  - test/support/test_helpers.ex (sample_* functions)
  - test/support/fixtures/api_responses.ex (API fixtures)
  - Various inline test data in individual test files
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}

  # ══════════════════════════════════════════════════════════════════════════════
  # Killmail Test Data
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a test killmail with reasonable defaults.

  Options:
  - killmail_id: integer (default: 123456)
  - victim_id: integer (default: 1001)
  - attacker_id: integer (default: 1002)
  - system_id: integer (default: 30000142)
  - ship_type_id: integer (default: 587)
  - value: integer (default: 150_000_000)
  """
  def build_killmail(opts \\ []) do
    killmail_id = Keyword.get(opts, :killmail_id, 123_456)
    victim_id = Keyword.get(opts, :victim_id, 1001)
    attacker_id = Keyword.get(opts, :attacker_id, 1002)
    system_id = Keyword.get(opts, :system_id, 30_000_142)
    ship_type_id = Keyword.get(opts, :ship_type_id, 587)
    value = Keyword.get(opts, :value, 150_000_000)

    victim_data = %{
      "character_id" => victim_id,
      "character_name" => "Test Victim",
      "corporation_id" => 2001,
      "corporation_name" => "Test Corp",
      "alliance_id" => 3001,
      "alliance_name" => "Test Alliance",
      "ship_type_id" => ship_type_id,
      "ship_name" => "Rifter",
      "damage_taken" => 5000
    }

    attackers_data = [
      %{
        "character_id" => attacker_id,
        "character_name" => "Test Attacker",
        "corporation_id" => 2002,
        "corporation_name" => "Attacker Corp",
        "ship_type_id" => ship_type_id + 1,
        "ship_name" => "Rifter",
        "final_blow" => true,
        "damage_done" => 5000
      }
    ]

    zkb_data = %{
      "locationID" => system_id,
      "hash" => "test_hash_#{killmail_id}",
      "fittedValue" => trunc(value * 0.7),
      "totalValue" => value,
      "points" => 1,
      "npc" => false,
      "solo" => false,
      "awox" => false
    }

    websocket_data = %{
      "victim" => victim_data,
      "attackers" => attackers_data,
      "zkb" => zkb_data,
      "kill_time" => "2024-01-01T12:00:00Z"
    }

    killmail_id
    |> to_string()
    |> Killmail.from_websocket_data(system_id, websocket_data)
  end

  @doc """
  Creates killmail data in the raw WebSocket format.
  """
  def build_websocket_killmail_data(opts \\ []) do
    killmail_id = Keyword.get(opts, :killmail_id, 123_456)
    victim_id = Keyword.get(opts, :victim_id, 1001)
    attacker_id = Keyword.get(opts, :attacker_id, 1002)
    system_id = Keyword.get(opts, :system_id, 30_000_142)
    value = Keyword.get(opts, :value, 150_000_000)

    %{
      "killmail_id" => killmail_id,
      "system_id" => system_id,
      "victim" => %{
        "character_id" => victim_id,
        "character_name" => "Test Victim",
        "corporation_id" => 2001,
        "corporation_name" => "Test Corp",
        "ship_type_id" => 587,
        "ship_name" => "Rifter",
        "damage_taken" => 5000
      },
      "attackers" => [
        %{
          "character_id" => attacker_id,
          "character_name" => "Test Attacker",
          "corporation_id" => 2002,
          "corporation_name" => "Attacker Corp",
          "ship_type_id" => 588,
          "final_blow" => true,
          "damage_done" => 5000
        }
      ],
      "zkb" => %{
        "locationID" => system_id,
        "hash" => "test_hash",
        "fittedValue" => trunc(value * 0.7),
        "totalValue" => value,
        "points" => 1
      },
      "kill_time" => "2024-01-01T12:00:00Z"
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Character Test Data
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a test character with reasonable defaults.

  Options:
  - character_id: string (default: "123456")
  - name: string (default: "Test Character")
  - corporation_id: integer (default: 2001)
  - alliance_id: integer (default: 3001)
  - corporation_ticker: string (default: "TEST")
  - alliance_ticker: string (default: "ALLY")
  """
  def build_character(opts \\ []) do
    attrs = %{
      "eve_id" => Keyword.get(opts, :character_id, "123456"),
      "name" => Keyword.get(opts, :name, "Test Character"),
      "corporation_id" => Keyword.get(opts, :corporation_id, 2001),
      "alliance_id" => Keyword.get(opts, :alliance_id, 3001),
      "corporation_ticker" => Keyword.get(opts, :corporation_ticker, "TEST"),
      "alliance_ticker" => Keyword.get(opts, :alliance_ticker, "ALLY")
    }

    %Character{
      character_id: attrs["character_id"],
      name: attrs["name"],
      corporation_id: attrs["corporation_id"],
      alliance_id: attrs["alliance_id"],
      eve_id: attrs["character_id"],
      corporation_ticker: attrs["corporation_ticker"],
      alliance_ticker: attrs["alliance_ticker"],
      tracked: false
    }
  end

  @doc """
  Creates character data in API response format.
  """
  def build_character_api_data(opts \\ []) do
    %{
      "eve_id" => Keyword.get(opts, :character_id, "123456"),
      "name" => Keyword.get(opts, :name, "Test Character"),
      "corporation_id" => Keyword.get(opts, :corporation_id, 2001),
      "alliance_id" => Keyword.get(opts, :alliance_id, 3001),
      "corporation_ticker" => Keyword.get(opts, :corporation_ticker, "TEST"),
      "alliance_ticker" => Keyword.get(opts, :alliance_ticker, "ALLY")
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # System Test Data
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a test system with reasonable defaults.

  Options:
  - solar_system_id: integer (default: 30000142)
  - name: string (default: "Jita")
  - region_name: string (default: "The Forge")
  - system_type: atom (default: :highsec)
  - security_status: float (default: 0.946)
  """
  def build_system(opts \\ []) do
    attrs = %{
      "solar_system_id" => Keyword.get(opts, :solar_system_id, 30_000_142),
      "name" => Keyword.get(opts, :name, "Jita"),
      "region_name" => Keyword.get(opts, :region_name, "The Forge"),
      "system_type" => Keyword.get(opts, :system_type, :highsec),
      "security_status" => Keyword.get(opts, :security_status, 0.946)
    }

    %System{
      solar_system_id: to_string(attrs["solar_system_id"]),
      name: attrs["name"],
      region_name: attrs["region_name"],
      system_type: to_string(attrs["system_type"]),
      security_status: attrs["security_status"],
      tracked: false
    }
  end

  @doc """
  Creates a wormhole system with wormhole-specific data.
  """
  def build_wormhole_system(opts \\ []) do
    attrs = %{
      "solar_system_id" => Keyword.get(opts, :solar_system_id, 31_001_234),
      "name" => Keyword.get(opts, :name, "J123456"),
      "system_type" => :wormhole,
      "class_title" => Keyword.get(opts, :class_title, "C4"),
      "is_shattered" => Keyword.get(opts, :is_shattered, false),
      "statics" => Keyword.get(opts, :statics, ["C247", "P060"]),
      "effect_name" => Keyword.get(opts, :effect_name, "Pulsar")
    }

    %System{
      solar_system_id: to_string(attrs["solar_system_id"]),
      name: attrs["name"],
      system_type: to_string(attrs["system_type"]),
      class_title: attrs["class_title"],
      is_shattered: attrs["is_shattered"],
      statics: attrs["statics"],
      effect_name: attrs["effect_name"],
      tracked: false
    }
  end

  @doc """
  Creates system data in API response format.
  """
  def build_system_api_data(opts \\ []) do
    %{
      "id" => to_string(Keyword.get(opts, :solar_system_id, 30_000_142)),
      "solar_system_id" => Keyword.get(opts, :solar_system_id, 30_000_142),
      "name" => Keyword.get(opts, :name, "Jita"),
      "region_name" => Keyword.get(opts, :region_name, "The Forge"),
      "security_status" => Keyword.get(opts, :security_status, 0.946)
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # ESI API Response Data
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates ESI character response data.
  """
  def build_esi_character_response(opts \\ []) do
    %{
      "character_id" => Keyword.get(opts, :character_id, 123_456),
      "name" => Keyword.get(opts, :name, "Test Character"),
      "corporation_id" => Keyword.get(opts, :corporation_id, 789_012),
      "alliance_id" => Keyword.get(opts, :alliance_id, 345_678),
      "security_status" => Keyword.get(opts, :security_status, 0.5),
      "birthday" => "2020-01-01T00:00:00Z"
    }
  end

  @doc """
  Creates ESI corporation response data.
  """
  def build_esi_corporation_response(opts \\ []) do
    %{
      "corporation_id" => Keyword.get(opts, :corporation_id, 789_012),
      "name" => Keyword.get(opts, :name, "Test Corporation"),
      "ticker" => Keyword.get(opts, :ticker, "TSTC"),
      "member_count" => Keyword.get(opts, :member_count, 100),
      "alliance_id" => Keyword.get(opts, :alliance_id, 345_678),
      "description" => "A test corporation",
      "date_founded" => "2020-01-01T00:00:00Z"
    }
  end

  @doc """
  Creates ESI alliance response data.
  """
  def build_esi_alliance_response(opts \\ []) do
    %{
      "alliance_id" => Keyword.get(opts, :alliance_id, 345_678),
      "name" => Keyword.get(opts, :name, "Test Alliance"),
      "ticker" => Keyword.get(opts, :ticker, "TSTA"),
      "executor_corporation_id" => Keyword.get(opts, :executor_corporation_id, 789_012),
      "creator_id" => 123_456,
      "date_founded" => "2020-01-01T00:00:00Z",
      "faction_id" => 555_555
    }
  end

  @doc """
  Creates ESI system response data.
  """
  def build_esi_system_response(opts \\ []) do
    %{
      "system_id" => Keyword.get(opts, :system_id, 30_000_142),
      "name" => Keyword.get(opts, :name, "Jita"),
      "constellation_id" => 20_000_020,
      "security_status" => Keyword.get(opts, :security_status, 0.9),
      "security_class" => "B",
      "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
      "star_id" => 40_000_001,
      "planets" => [%{"planet_id" => 50_000_001}],
      "region_id" => 10_000_002
    }
  end

  @doc """
  Creates ESI type response data.
  """
  def build_esi_type_response(opts \\ []) do
    %{
      "type_id" => Keyword.get(opts, :type_id, 587),
      "name" => Keyword.get(opts, :name, "Rifter"),
      "group_id" => 25,
      "category_id" => 6,
      "volume" => 27_289.5,
      "description" => "A test ship type"
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Map API Response Data
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates map API character list response.
  """
  def build_map_characters_response(count \\ 3) do
    %{
      "data" =>
        Enum.map(1..count, fn i ->
          %{
            "eve_id" => "#{123_000 + i}",
            "name" => "Character #{i}",
            "corporation_id" => 2000 + i,
            "corporation_ticker" => "TC#{i}",
            "alliance_id" => if(i > 1, do: 3000 + i, else: nil),
            "alliance_ticker" => if(i > 1, do: "TA#{i}", else: nil)
          }
        end)
    }
  end

  @doc """
  Creates map API systems list response.
  """
  def build_map_systems_response(count \\ 3) do
    %{
      "data" =>
        Enum.map(1..count, fn i ->
          %{
            "id" => "#{30_000_000 + i}",
            "solar_system_id" => 30_000_000 + i,
            "name" => "System #{i}",
            "region_name" => "Region #{i}",
            "security_status" => 0.5 + i * 0.1
          }
        end)
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Discord API Response Data
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates Discord message response data.
  """
  def build_discord_message_response(opts \\ []) do
    %{
      "id" => Keyword.get(opts, :message_id, "123456789"),
      "content" => Keyword.get(opts, :content, "Test message"),
      "channel_id" => Keyword.get(opts, :channel_id, "987654321"),
      "author" => %{
        "id" => "bot_id",
        "username" => "Test Bot"
      },
      "timestamp" => "2024-01-01T12:00:00Z"
    }
  end

  @doc """
  Creates Discord embed response data.
  """
  def build_discord_embed_response(opts \\ []) do
    %{
      "id" => Keyword.get(opts, :message_id, "123456789"),
      "embeds" => [
        %{
          "title" => Keyword.get(opts, :title, "Test Embed"),
          "description" => Keyword.get(opts, :description, "Test description"),
          "color" => Keyword.get(opts, :color, 0x3498DB),
          "url" => Keyword.get(opts, :url, "https://example.com")
        }
      ],
      "channel_id" => Keyword.get(opts, :channel_id, "987654321")
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Builder Pattern Helpers
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a list of test killmails with incremented IDs.
  """
  def build_killmail_list(count, base_opts \\ []) do
    Enum.map(1..count, fn i ->
      opts =
        Keyword.merge(base_opts,
          killmail_id: 123_000 + i,
          victim_id: 1000 + i,
          attacker_id: 2000 + i
        )

      build_killmail(opts)
    end)
  end

  @doc """
  Creates a list of test characters with incremented IDs.
  """
  def build_character_list(count, base_opts \\ []) do
    Enum.map(1..count, fn i ->
      opts =
        Keyword.merge(base_opts,
          character_id: "#{123_000 + i}",
          name: "Character #{i}",
          corporation_ticker: "TC#{i}"
        )

      build_character(opts)
    end)
  end

  @doc """
  Creates a list of test systems with incremented IDs.
  """
  def build_system_list(count, base_opts \\ []) do
    Enum.map(1..count, fn i ->
      opts =
        Keyword.merge(base_opts,
          solar_system_id: 30_000_000 + i,
          name: "System #{i}",
          region_name: "Region #{rem(i, 3) + 1}"
        )

      build_system(opts)
    end)
  end
end
