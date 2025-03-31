defmodule WandererNotifier.Config.DebugTest do
  use ExUnit.Case, async: false
  alias WandererNotifier.Config.Debug

  # Save original environment before tests
  setup do
    # Save original environment variables
    original_env = System.get_env("WANDERER_DEBUG_LOGGING")
    original_map_url = Application.get_env(:wanderer_notifier, :map_url)
    original_map_token = Application.get_env(:wanderer_notifier, :map_token)
    original_map_name = Application.get_env(:wanderer_notifier, :map_name)
    original_map_url_with_name = Application.get_env(:wanderer_notifier, :map_url_with_name)
    original_config = Application.get_env(:wanderer_notifier, :debug_logging_enabled)

    # Clean up after tests
    on_exit(fn ->
      # Restore original environment
      if is_nil(original_env) do
        System.delete_env("WANDERER_DEBUG_LOGGING")
      else
        System.put_env("WANDERER_DEBUG_LOGGING", original_env)
      end

      # Restore original config
      if is_nil(original_config) do
        Application.delete_env(:wanderer_notifier, :debug_logging_enabled)
      else
        Application.put_env(:wanderer_notifier, :debug_logging_enabled, original_config)
      end

      # Restore map settings
      restore_or_delete_config(:map_url, original_map_url)
      restore_or_delete_config(:map_token, original_map_token)
      restore_or_delete_config(:map_name, original_map_name)
      restore_or_delete_config(:map_url_with_name, original_map_url_with_name)
    end)

    :ok
  end

  # Helper to restore or delete config
  defp restore_or_delete_config(key, value) do
    if is_nil(value) do
      Application.delete_env(:wanderer_notifier, key)
    else
      Application.put_env(:wanderer_notifier, key, value)
    end
  end

  describe "debug_logging_enabled?/0" do
    test "returns false by default" do
      # Clear the environment and configuration
      System.delete_env("WANDERER_DEBUG_LOGGING")
      Application.delete_env(:wanderer_notifier, :debug_logging_enabled)

      refute Debug.debug_logging_enabled?()
    end

    test "returns true when enabled via environment variable" do
      System.put_env("WANDERER_DEBUG_LOGGING", "true")
      Application.delete_env(:wanderer_notifier, :debug_logging_enabled)

      assert Debug.debug_logging_enabled?()
    end

    test "returns true when enabled via config" do
      System.delete_env("WANDERER_DEBUG_LOGGING")
      Application.put_env(:wanderer_notifier, :debug_logging_enabled, true)

      assert Debug.debug_logging_enabled?()
    end

    test "config takes precedence over environment variable" do
      System.put_env("WANDERER_DEBUG_LOGGING", "false")
      Application.put_env(:wanderer_notifier, :debug_logging_enabled, true)

      assert Debug.debug_logging_enabled?()
    end
  end

  describe "toggle_debug_logging/0" do
    test "toggles debug logging from false to true" do
      # Ensure debug logging is disabled
      System.delete_env("WANDERER_DEBUG_LOGGING")
      Application.delete_env(:wanderer_notifier, :debug_logging_enabled)

      # Toggle debug logging
      assert Debug.toggle_debug_logging() == true

      # Verify the setting was updated
      assert Debug.debug_logging_enabled?()
    end

    test "toggles debug logging from true to false" do
      # Ensure debug logging is enabled
      Application.put_env(:wanderer_notifier, :debug_logging_enabled, true)

      # Toggle debug logging
      assert Debug.toggle_debug_logging() == false

      # Verify the setting was updated
      refute Debug.debug_logging_enabled?()
    end
  end

  describe "set_debug_logging/1" do
    test "sets debug logging to true" do
      Application.delete_env(:wanderer_notifier, :debug_logging_enabled)

      assert Debug.set_debug_logging(true) == true
      assert Debug.debug_logging_enabled?()
    end

    test "sets debug logging to false" do
      Application.put_env(:wanderer_notifier, :debug_logging_enabled, true)

      assert Debug.set_debug_logging(false) == false
      refute Debug.debug_logging_enabled?()
    end
  end

  describe "map_debug_settings/0" do
    setup do
      # Clear application configuration before each test
      Application.delete_env(:wanderer_notifier, :map_url)
      Application.delete_env(:wanderer_notifier, :map_token)
      Application.delete_env(:wanderer_notifier, :map_name)
      Application.delete_env(:wanderer_notifier, :map_url_with_name)

      :ok
    end

    test "returns default values when not configured" do
      # Clear all environment variables that could affect the test
      [
        "MAP_URL",
        "MAP_TOKEN",
        "MAP_NAME",
        "MAP_URL_WITH_NAME",
        "WANDERER_MAP_URL",
        "WANDERER_MAP_TOKEN",
        "WANDERER_MAP_NAME",
        "WANDERER_MAP_URL_WITH_NAME"
      ]
      |> Enum.each(&System.delete_env/1)

      settings = Debug.map_debug_settings()

      assert is_map(settings)
      assert is_nil(settings.map_url)
      assert is_nil(settings.map_token)
      assert is_nil(settings.map_name)
      assert is_nil(settings.map_url_with_name)
    end

    test "returns values from environment variables" do
      # Clear any existing env vars first
      ["MAP_URL", "MAP_TOKEN", "WANDERER_MAP_URL", "WANDERER_MAP_TOKEN"]
      |> Enum.each(&System.delete_env/1)

      System.put_env("WANDERER_MAP_URL", "https://example.com/map")
      System.put_env("WANDERER_MAP_TOKEN", "test-token")

      settings = Debug.map_debug_settings()

      assert settings.map_url == "https://example.com/map"
      assert settings.map_token == "test-token"
    end

    test "supports legacy environment variables for backward compatibility" do
      # Clear any existing env vars first
      ["MAP_URL", "MAP_TOKEN", "WANDERER_MAP_URL", "WANDERER_MAP_TOKEN"]
      |> Enum.each(&System.delete_env/1)

      System.put_env("MAP_URL", "https://example.com/map")
      System.put_env("MAP_TOKEN", "test-token")

      settings = Debug.map_debug_settings()

      assert settings.map_url == "https://example.com/map"
      assert settings.map_token == "test-token"
    end

    test "prefixed variables take precedence over legacy variables" do
      # Setup both new and legacy variables with different values
      System.put_env("WANDERER_MAP_URL", "https://wanderer.example.com")
      System.put_env("MAP_URL", "https://legacy.example.com")

      settings = Debug.map_debug_settings()

      assert settings.map_url == "https://wanderer.example.com"
    end
  end
end
