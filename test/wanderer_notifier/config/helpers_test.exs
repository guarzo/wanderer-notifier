defmodule WandererNotifier.Config.HelpersTest do
  use ExUnit.Case, async: true

  defmodule TestConfig do
    require WandererNotifier.Config.Helpers
    import WandererNotifier.Config.Helpers, except: [get: 1, get: 2, feature_enabled?: 1]

    # Test simple configuration accessors
    defconfig(:simple, [
      :test_token,
      :test_url
    ])

    # Test configuration with defaults
    defconfig(:with_defaults, [
      {:test_port, 4000},
      {:test_timeout, 30_000}
    ])

    # Test feature flags
    defconfig(:features, [
      :test_feature_enabled,
      :another_feature_enabled
    ])

    # Test channel accessors
    defconfig(:channels, [
      :test_discord_main,
      :test_discord_alerts
    ])

    # Implement required delegated functions for testing
    def get(key, default \\ nil) do
      case key do
        :test_token -> "test_token_value"
        :test_url -> "https://test.example.com"
        :test_port -> 8080
        :test_timeout -> 45_000
        _ -> default
      end
    end

    def feature_enabled?(flag) do
      case flag do
        :test_feature_enabled -> true
        :another_feature_enabled -> false
        _ -> false
      end
    end
  end

  describe "simple configuration accessors" do
    test "generates accessors for simple config keys" do
      assert TestConfig.test_token() == "test_token_value"
      assert TestConfig.test_url() == "https://test.example.com"
    end
  end

  describe "configuration with defaults" do
    test "uses configured values when available" do
      # From mock get/2
      assert TestConfig.test_port() == 8080
      # From mock get/2
      assert TestConfig.test_timeout() == 45_000
    end
  end

  describe "feature flag accessors" do
    test "generates feature flag accessors with ? suffix" do
      assert TestConfig.test_feature_enabled?() == true
      assert TestConfig.another_feature_enabled?() == false
    end
  end

  describe "channel accessors" do
    test "generates channel ID accessors" do
      # These should call get with the _channel_id suffix
      assert function_exported?(TestConfig, :test_discord_main_channel_id, 0)
      assert function_exported?(TestConfig, :test_discord_alerts_channel_id, 0)
    end
  end

  describe "helper functions" do
    test "fetch_env_string returns environment value or default" do
      # Mock environment provider module
      defmodule MockEnvProvider do
        def get_env("TEST_KEY", _default), do: "env_value"
        def get_env(_key, default), do: default
      end

      Application.put_env(:wanderer_notifier, :env_provider, MockEnvProvider)

      result = WandererNotifier.Config.Helpers.fetch_env_string("TEST_KEY", "default")
      assert result == "env_value"

      result = WandererNotifier.Config.Helpers.fetch_env_string("MISSING_KEY", "fallback")
      assert result == "fallback"
    end

    test "fetch_env_int parses integer values correctly" do
      defmodule MockEnvProviderInt do
        def get_env("PORT"), do: "8080"
        def get_env("PORT", _default), do: "8080"
        def get_env(_key), do: nil
        def get_env(_key, default), do: default
      end

      Application.put_env(:wanderer_notifier, :env_provider, MockEnvProviderInt)

      result = WandererNotifier.Config.Helpers.fetch_env_int("PORT", 4000)
      assert result == 8080

      result = WandererNotifier.Config.Helpers.fetch_env_int("MISSING_PORT", 9000)
      assert result == 9000
    end

    test "fetch_env_bool parses boolean values correctly" do
      defmodule MockEnvProviderBool do
        def get_env("ENABLED"), do: "true"
        def get_env("DISABLED"), do: "false"
        def get_env("ENABLED", _default), do: "true"
        def get_env("DISABLED", _default), do: "false"
        def get_env(_key), do: nil
        def get_env(_key, default), do: default
      end

      Application.put_env(:wanderer_notifier, :env_provider, MockEnvProviderBool)

      result = WandererNotifier.Config.Helpers.fetch_env_bool("ENABLED", false)
      assert result == true

      result = WandererNotifier.Config.Helpers.fetch_env_bool("DISABLED", true)
      assert result == false

      result = WandererNotifier.Config.Helpers.fetch_env_bool("MISSING", false)
      assert result == false
    end
  end
end
