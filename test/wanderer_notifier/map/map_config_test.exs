defmodule WandererNotifier.Map.MapConfigTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.MapConfig

  defp config_with_excludes(list) do
    %MapConfig{
      slug: "test",
      name: "Test",
      map_id: "test",
      settings: %{
        corporation_kill_focus: [],
        character_exclude_list: [],
        system_exclude_list: list
      }
    }
  end

  describe "system_exclude_list/1" do
    test "returns the configured list" do
      assert MapConfig.system_exclude_list(config_with_excludes([30_000_142, 30_002_187])) ==
               [30_000_142, 30_002_187]
    end

    test "returns an empty list when none configured" do
      assert MapConfig.system_exclude_list(config_with_excludes([])) == []
    end
  end

  describe "system_excluded?/2" do
    test "returns true when integer system id matches" do
      assert MapConfig.system_excluded?(config_with_excludes([30_000_142]), 30_000_142)
    end

    test "returns false when integer system id does not match" do
      refute MapConfig.system_excluded?(config_with_excludes([30_000_142]), 30_002_187)
    end

    test "returns true when binary system id matches a configured integer" do
      assert MapConfig.system_excluded?(config_with_excludes([30_000_142]), "30000142")
    end

    test "returns false for non-numeric binary system ids" do
      refute MapConfig.system_excluded?(config_with_excludes([30_000_142]), "not-a-number")
    end

    test "returns false for nil system id" do
      refute MapConfig.system_excluded?(config_with_excludes([30_000_142]), nil)
    end

    test "returns false when exclude list is empty" do
      refute MapConfig.system_excluded?(config_with_excludes([]), 30_000_142)
    end
  end

  describe "parse_settings via from_api/1" do
    test "coerces system_exclude_list to integers" do
      data = %{
        "slug" => "alpha",
        "name" => "Alpha",
        "map_id" => "alpha-id",
        "settings" => %{
          "system_exclude_list" => [30_000_142, "30002187", "not-a-number", nil]
        }
      }

      assert {:ok, %MapConfig{} = config} = MapConfig.from_api(data)
      assert config.settings.system_exclude_list == [30_000_142, 30_002_187]
    end
  end
end
