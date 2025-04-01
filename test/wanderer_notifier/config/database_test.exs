defmodule WandererNotifier.Config.DatabaseTest do
  use ExUnit.Case, async: false
  alias WandererNotifier.Config.Database

  # Save the original environment before running tests
  setup do
    # Store original database configuration
    original_config = Application.get_env(:wanderer_notifier, :database)

    # Ensure we clean up after tests run
    on_exit(fn ->
      if original_config do
        Application.put_env(:wanderer_notifier, :database, original_config)
      else
        Application.delete_env(:wanderer_notifier, :database)
      end
    end)

    :ok
  end

  describe "config/0" do
    test "returns a complete configuration map" do
      # Set test values
      Application.put_env(:wanderer_notifier, :database, %{
        username: "test_user",
        password: "test_password",
        hostname: "test_host",
        database: "test_db",
        port: "5433",
        pool_size: "5"
      })

      config = Database.config()

      assert config.username == "test_user"
      assert config.password == "test_password"
      assert config.hostname == "test_host"
      assert config.database == "test_db"
      assert config.port == 5433
      assert config.pool_size == 5
    end
  end

  describe "validation" do
    test "validate/0 returns :ok for valid configuration" do
      # Set valid test values
      Application.put_env(:wanderer_notifier, :database, %{
        username: "test_user",
        password: "test_password",
        hostname: "test_host",
        database: "test_db",
        port: "5433",
        pool_size: "5"
      })

      assert Database.validate() == :ok
    end

    test "validate/0 returns error for empty username" do
      # Set invalid test values
      Application.put_env(:wanderer_notifier, :database, %{
        username: "",
        password: "test_password",
        hostname: "test_host",
        database: "test_db"
      })

      assert Database.validate() == {:error, "Database username cannot be empty"}
    end

    test "validate/0 returns error for empty password" do
      # Set invalid test values
      Application.put_env(:wanderer_notifier, :database, %{
        username: "test_user",
        password: "",
        hostname: "test_host",
        database: "test_db"
      })

      assert Database.validate() == {:error, "Database password cannot be empty"}
    end
  end

  describe "default values" do
    test "returns default values when configuration is empty" do
      # Ensure no config is set
      Application.delete_env(:wanderer_notifier, :database)

      assert Database.username() == "postgres"
      assert Database.password() == "postgres"
      assert Database.hostname() == "postgres"
      # Database name depends on environment, so we don't test exact value
      assert is_binary(Database.database_name())
      assert Database.port() == 5432
      assert Database.pool_size() == 10
    end
  end
end
