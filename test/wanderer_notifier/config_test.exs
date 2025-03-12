defmodule WandererNotifier.ConfigTest do
  use ExUnit.Case
  alias WandererNotifier.Config

  setup do
    # Reset environment variables before each test
    Application.delete_env(:wanderer_notifier, :license_key)
    Application.delete_env(:wanderer_notifier, :license_manager_api_url)
    Application.delete_env(:wanderer_notifier, :bot_registration_token)

    :ok
  end

  describe "license_key/0" do
    test "returns nil when not set" do
      assert Config.license_key() == nil
    end

    test "returns the license key when set" do
      Application.put_env(:wanderer_notifier, :license_key, "test-license-key")
      assert Config.license_key() == "test-license-key"
    end
  end

  describe "license_manager_api_url/0" do
    test "returns nil when not set" do
      assert Config.license_manager_api_url() == nil
    end

    test "returns the license manager API URL when set" do
      Application.put_env(:wanderer_notifier, :license_manager_api_url, "https://api.example.com")
      assert Config.license_manager_api_url() == "https://api.example.com"
    end
  end

  describe "bot_registration_token/0" do
    test "returns nil when not set" do
      assert Config.bot_registration_token() == nil
    end

    test "returns the bot token when set" do
      Application.put_env(:wanderer_notifier, :bot_registration_token, "reg-token-123")
      assert Config.bot_registration_token() == "reg-token-123"
    end
  end

  describe "bot_type/0" do
    test "returns the correct bot type" do
      assert Config.bot_type() == "wanderer_notifier"
    end
  end

  describe "get_env!/1" do
    test "raises an error when the environment variable is not set" do
      assert_raise RuntimeError, "Missing test_key configuration", fn ->
        Config.get_env!(:test_key)
      end
    end

    test "returns the value when the environment variable is set" do
      Application.put_env(:wanderer_notifier, :test_key, "test-value")
      assert Config.get_env!(:test_key) == "test-value"
    end
  end

  describe "get_env/1" do
    test "returns nil when the environment variable is not set" do
      assert Config.get_env(:test_key) == nil
    end

    test "returns the value when the environment variable is set" do
      Application.put_env(:wanderer_notifier, :test_key, "test-value")
      assert Config.get_env(:test_key) == "test-value"
    end
  end
end
