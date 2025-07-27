defmodule WandererNotifier.Shared.Config.SchemaTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Shared.Config.Schema

  describe "schema/0" do
    test "returns complete configuration schema" do
      schema = Schema.schema()

      assert is_map(schema)
      assert map_size(schema) > 0

      # Check that all fields have required properties
      for {field, config} <- schema do
        assert is_atom(field), "Field #{field} should be an atom"
        assert is_map(config), "Config for #{field} should be a map"
        assert Map.has_key?(config, :type), "#{field} missing :type"
        assert Map.has_key?(config, :required), "#{field} missing :required"
        assert Map.has_key?(config, :default), "#{field} missing :default"
        assert Map.has_key?(config, :env_var), "#{field} missing :env_var"
        assert Map.has_key?(config, :description), "#{field} missing :description"
      end
    end

    test "includes all expected configuration fields" do
      schema = Schema.schema()

      expected_fields = [
        # Discord
        :discord_bot_token,
        :discord_application_id,
        :discord_channel_id,
        :discord_character_channel_id,
        :discord_system_channel_id,

        # Map Integration
        :map_url,
        :map_name,
        :map_api_key,

        # Service URLs
        :websocket_url,
        :wanderer_kills_url,
        :license_manager_url,

        # License & Auth
        :license_key,

        # Feature Flags
        :notifications_enabled,
        :kill_notifications_enabled,
        :system_notifications_enabled,
        :character_notifications_enabled,
        :enable_status_messages,
        :track_kspace_enabled,
        :priority_systems_only,

        # Application Settings
        :port,
        :host,
        :scheme,
        :public_url
      ]

      for field <- expected_fields do
        assert Map.has_key?(schema, field), "Missing field: #{field}"
      end
    end

    test "has correct field types" do
      schema = Schema.schema()

      # String fields
      string_fields = [
        :discord_bot_token,
        :discord_application_id,
        :discord_channel_id,
        :map_name,
        :map_api_key,
        :license_key,
        :host,
        :scheme
      ]

      for field <- string_fields do
        assert schema[field].type == :string, "#{field} should be string type"
      end

      # URL fields
      url_fields = [
        :map_url,
        :websocket_url,
        :wanderer_kills_url,
        :license_manager_url,
        :public_url
      ]

      for field <- url_fields do
        assert schema[field].type == :url, "#{field} should be url type"
      end

      # Boolean fields
      boolean_fields = [
        :notifications_enabled,
        :kill_notifications_enabled,
        :system_notifications_enabled,
        :character_notifications_enabled,
        :enable_status_messages,
        :track_kspace_enabled,
        :priority_systems_only
      ]

      for field <- boolean_fields do
        assert schema[field].type == :boolean, "#{field} should be boolean type"
      end

      # Integer fields
      assert schema[:port].type == :integer
    end

    test "has correct required field markings" do
      schema = Schema.schema()

      # Required fields
      required_fields = [
        :discord_bot_token,
        :map_url,
        :map_name,
        :map_api_key,
        :license_key
      ]

      for field <- required_fields do
        assert schema[field].required == true, "#{field} should be required"
      end

      # Optional fields (check a few examples)
      optional_fields = [
        :discord_application_id,
        :discord_channel_id,
        :notifications_enabled,
        :port,
        :host
      ]

      for field <- optional_fields do
        assert schema[field].required == false, "#{field} should be optional"
      end
    end

    test "has environment variables mapped correctly" do
      schema = Schema.schema()

      # Check that env vars don't have WANDERER_ prefix (new simplified format)
      # except for wanderer_kills_url which is an exception
      for {field, config} <- schema do
        env_var = config.env_var

        if field != :wanderer_kills_url do
          refute String.starts_with?(env_var, "WANDERER_"),
                 "#{field} env var #{env_var} should not have WANDERER_ prefix"
        end
      end

      # Check specific mappings
      assert schema[:discord_bot_token].env_var == "DISCORD_BOT_TOKEN"
      assert schema[:map_url].env_var == "MAP_URL"
      assert schema[:notifications_enabled].env_var == "NOTIFICATIONS_ENABLED"
      assert schema[:port].env_var == "PORT"
    end

    test "has sensible default values" do
      schema = Schema.schema()

      # Check defaults for optional fields
      assert schema[:notifications_enabled].default == true
      assert schema[:port].default == 4000
      assert schema[:host].default == "localhost"
      assert schema[:scheme].default == "http"
      assert schema[:websocket_url].default == "ws://host.docker.internal:4004"

      # Required fields should have nil defaults
      required_with_nil_defaults = [
        :discord_bot_token,
        :map_url,
        :map_name,
        :map_api_key,
        :license_key
      ]

      for field <- required_with_nil_defaults do
        assert schema[field].default == nil, "#{field} should have nil default"
      end
    end

    test "has descriptions for all fields" do
      schema = Schema.schema()

      for {field, config} <- schema do
        description = config.description
        assert is_binary(description), "#{field} description should be a string"
        assert String.length(description) > 0, "#{field} description should not be empty"
        assert String.length(description) > 10, "#{field} description should be descriptive"
      end
    end
  end

  describe "required_fields/0" do
    test "returns all required fields" do
      required_fields = Schema.required_fields()

      assert is_list(required_fields)
      assert length(required_fields) > 0

      # Check that all returned fields are actually marked as required
      schema = Schema.schema()

      for field <- required_fields do
        assert schema[field].required == true, "#{field} should be required in schema"
      end
    end

    test "includes expected required fields" do
      required_fields = Schema.required_fields()

      expected_required = [
        :discord_bot_token,
        :map_url,
        :map_name,
        :map_api_key,
        :license_key
      ]

      for field <- expected_required do
        assert field in required_fields, "#{field} should be in required fields"
      end
    end
  end

  describe "environment_fields/1" do
    test "returns correct fields for each environment" do
      # Development and test should have no specific requirements
      assert Schema.environment_fields(:dev) == []
      assert Schema.environment_fields(:test) == []

      # Production should require all required fields
      prod_fields = Schema.environment_fields(:prod)
      required_fields = Schema.required_fields()

      assert prod_fields == required_fields
    end
  end

  describe "env_var_for_field/1" do
    test "returns correct environment variable names" do
      assert Schema.env_var_for_field(:discord_bot_token) == "DISCORD_BOT_TOKEN"
      assert Schema.env_var_for_field(:map_url) == "MAP_URL"
      assert Schema.env_var_for_field(:notifications_enabled) == "NOTIFICATIONS_ENABLED"
      assert Schema.env_var_for_field(:nonexistent_field) == nil
    end
  end

  describe "default_for_field/1" do
    test "returns correct default values" do
      assert Schema.default_for_field(:notifications_enabled) == true
      assert Schema.default_for_field(:port) == 4000
      assert Schema.default_for_field(:discord_bot_token) == nil
      assert Schema.default_for_field(:nonexistent_field) == nil
    end
  end

  describe "field validation functions" do
    test "validates Discord snowflake IDs correctly" do
      # Valid snowflake
      valid_id = "123456789012345678"

      assert :ok ==
               WandererNotifier.Shared.Config.Validator.validate_field(
                 :discord_application_id,
                 valid_id
               )

      # Invalid snowflakes
      # Too long
      invalid_ids = ["123", "not_numeric", "12345678901234567890123"]

      for id <- invalid_ids do
        assert {:error, _} =
                 WandererNotifier.Shared.Config.Validator.validate_field(
                   :discord_application_id,
                   id
                 )
      end
    end

    test "validates URLs correctly" do
      # Valid URLs
      valid_urls = [
        "https://api.example.com",
        "http://localhost:4000",
        "https://sub.domain.com/path"
      ]

      for url <- valid_urls do
        assert :ok == WandererNotifier.Shared.Config.Validator.validate_field(:map_url, url)
      end

      # Invalid URLs
      invalid_urls = ["not_a_url", "://example.com", ""]

      for url <- invalid_urls do
        assert {:error, _} =
                 WandererNotifier.Shared.Config.Validator.validate_field(:map_url, url)
      end
    end

    test "validates WebSocket URLs correctly" do
      # Valid WebSocket URLs
      valid_ws_urls = [
        "ws://localhost:4004",
        "wss://secure.example.com/ws"
      ]

      for url <- valid_ws_urls do
        assert :ok == WandererNotifier.Shared.Config.Validator.validate_field(:websocket_url, url)
      end

      # Invalid WebSocket URLs
      invalid_ws_urls = ["http://example.com", "not_a_url", "ftp://example.com"]

      for url <- invalid_ws_urls do
        assert {:error, _} =
                 WandererNotifier.Shared.Config.Validator.validate_field(:websocket_url, url)
      end
    end

    test "validates ports correctly" do
      # Valid ports
      valid_ports = [80, 443, 4000, 8080, 65_535]

      for port <- valid_ports do
        assert :ok == WandererNotifier.Shared.Config.Validator.validate_field(:port, port)
      end

      # Invalid ports
      invalid_ports = [0, -1, 70_000, "4000"]

      for port <- invalid_ports do
        assert {:error, _} = WandererNotifier.Shared.Config.Validator.validate_field(:port, port)
      end
    end

    test "validates schemes correctly" do
      # Valid schemes
      for scheme <- ["http", "https"] do
        assert :ok == WandererNotifier.Shared.Config.Validator.validate_field(:scheme, scheme)
      end

      # Invalid schemes
      invalid_schemes = ["ftp", "ws", "file", ""]

      for scheme <- invalid_schemes do
        assert {:error, _} =
                 WandererNotifier.Shared.Config.Validator.validate_field(:scheme, scheme)
      end
    end
  end
end
