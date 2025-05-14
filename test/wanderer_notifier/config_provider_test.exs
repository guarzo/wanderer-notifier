defmodule WandererNotifier.ConfigProviderTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.ConfigProvider

  describe "init/1" do
    test "returns config unchanged" do
      config = %{test: :value}
      assert ConfigProvider.init(config) == config
    end
  end

  describe "load/1" do
    test "delegates to load/2 with empty options" do
      # Test directly with a simple configuration
      config = %{sample: :config}

      # Add something to the environment we can detect
      System.put_env("WANDERER_SAMPLE_TEST", "test_value")

      # Call the load/1 method
      result_with_load_1 = ConfigProvider.load(config)

      # Call the load/2 method directly for comparison
      result_with_load_2 = ConfigProvider.load(config, [])

      # Verify they return the same result
      assert result_with_load_1 == result_with_load_2

      # Clean up
      System.delete_env("WANDERER_SAMPLE_TEST")
    end
  end

  describe "load/2" do
    setup do
      # Store original env vars
      original_env = %{
        "PORT" => System.get_env("PORT"),
        "WANDERER_NOTIFICATIONS_ENABLED" => System.get_env("WANDERER_NOTIFICATIONS_ENABLED"),
        "WANDERER_CHARACTER_EXCLUDE_LIST" => System.get_env("WANDERER_CHARACTER_EXCLUDE_LIST")
      }

      # Clean any test env vars before testing
      System.delete_env("PORT")
      System.delete_env("WANDERER_NOTIFICATIONS_ENABLED")
      System.delete_env("WANDERER_CHARACTER_EXCLUDE_LIST")

      # Cleanup env vars after test
      on_exit(fn ->
        Enum.each(original_env, fn {key, val} ->
          if val do
            System.put_env(key, val)
          else
            System.delete_env(key)
          end
        end)
      end)

      %{original_env: original_env}
    end

    test "correctly parses PORT" do
      System.put_env("PORT", "8080")
      config = %{}

      result = ConfigProvider.load(config, [])

      assert get_in(result, [:wanderer_notifier, :port]) == 8080
    end

    test "correctly handles invalid PORT" do
      System.put_env("PORT", "invalid")
      config = %{}

      result = ConfigProvider.load(config, [])

      assert get_in(result, [:wanderer_notifier, :port]) == 4000
    end

    test "correctly parses boolean values" do
      test_cases = [
        {"true", true},
        {"TRUE", true},
        {"1", true},
        {"yes", true},
        {"y", true},
        {"t", true},
        {"on", true},
        {"false", false},
        {"FALSE", false},
        {"0", false},
        {"no", false},
        {"n", false},
        {"f", false},
        {"off", false},
        # default is true
        {"", true},
        # default is true
        {"invalid", true}
      ]

      Enum.each(test_cases, fn {input, expected} ->
        System.delete_env("WANDERER_NOTIFICATIONS_ENABLED")
        System.put_env("WANDERER_NOTIFICATIONS_ENABLED", input)
        config = %{}

        result = ConfigProvider.load(config, [])

        assert get_in(result, [:wanderer_notifier, :features, :notifications_enabled]) ==
                 expected,
               "Expected '#{input}' to parse as '#{expected}'"
      end)
    end

    test "correctly splits comma-separated values" do
      System.put_env("WANDERER_CHARACTER_EXCLUDE_LIST", "character1, character2,character3")
      config = %{}

      result = ConfigProvider.load(config, [])

      assert get_in(result, [:wanderer_notifier, :character_exclude_list]) == [
               "character1",
               "character2",
               "character3"
             ]
    end

    test "applies default values when env var is not present" do
      System.delete_env("PORT")
      config = %{}

      result = ConfigProvider.load(config, [])

      assert get_in(result, [:wanderer_notifier, :port]) == 4000
    end
  end
end
