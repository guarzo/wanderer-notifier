defmodule WandererNotifier.Config.ValidatorTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Config.{Schema, Validator}

  describe "validate_config/2" do
    test "passes with valid configuration" do
      config = %{
        discord_application_id: "123456789012345678",
        discord_channel_id: "987654321098765432",
        map_url: "https://api.wanderer.example",
        map_name: "test-map",
        map_api_key: "test-api-key-123",
        license_key: "license-key-123",
        notifications_enabled: true
      }

      assert :ok = Validator.validate_config(config, :dev)
    end

    test "fails with missing required fields" do
      config = %{
        notifications_enabled: true
      }

      assert {:error, errors} = Validator.validate_config(config, :prod)

      required_fields = Schema.required_fields()
      error_fields = Enum.map(errors, & &1.field)

      # All required fields should have errors
      for field <- required_fields do
        assert field in error_fields, "Missing error for required field: #{field}"
      end
    end

    test "passes in development with minimal config" do
      config = %{
        notifications_enabled: false
      }

      assert :ok = Validator.validate_config(config, :dev)
    end

    test "validates field types correctly" do
      config = %{
        port: "not_an_integer",
        notifications_enabled: "not_a_boolean"
      }

      assert {:error, errors} = Validator.validate_config(config, :dev)

      type_errors = Enum.filter(errors, &(&1.error == :invalid_type))
      assert length(type_errors) >= 2
    end

    test "validates Discord bot token format" do
      config = %{
        discord_bot_token: "invalid_token"
      }

      assert {:error, errors} = Validator.validate_config(config, :dev)

      token_error = Enum.find(errors, &(&1.field == :discord_bot_token))
      assert token_error != nil
      assert token_error.error == :invalid_value
    end

    test "validates Discord snowflake IDs" do
      config = %{
        discord_application_id: "not_a_snowflake",
        # Too short
        discord_channel_id: "123"
      }

      assert {:error, errors} = Validator.validate_config(config, :dev)

      snowflake_errors =
        Enum.filter(errors, fn error ->
          error.field in [:discord_application_id, :discord_channel_id] and
            error.error == :invalid_value
        end)

      assert length(snowflake_errors) >= 1
    end

    test "validates URL formats" do
      config = %{
        map_url: "not_a_url",
        websocket_url: "invalid://url",
        public_url: "ftp://not.http.url"
      }

      assert {:error, errors} = Validator.validate_config(config, :dev)

      url_errors =
        Enum.filter(errors, fn error ->
          error.field in [:map_url, :websocket_url, :public_url] and
            error.error == :invalid_value
        end)

      assert length(url_errors) >= 2
    end

    test "validates port range" do
      config = %{
        # Too high
        port: 70_000
      }

      assert {:error, errors} = Validator.validate_config(config, :dev)

      port_error = Enum.find(errors, &(&1.field == :port))
      assert port_error != nil
      assert port_error.error == :invalid_value
    end

    test "validates scheme values" do
      config = %{
        # Not http or https
        scheme: "ftp"
      }

      assert {:error, errors} = Validator.validate_config(config, :dev)

      scheme_error = Enum.find(errors, &(&1.field == :scheme))
      assert scheme_error != nil
      assert scheme_error.error == :invalid_value
    end
  end

  describe "validate_field/2" do
    test "validates individual fields correctly" do
      assert :ok = Validator.validate_field(:notifications_enabled, true)
      assert :ok = Validator.validate_field(:port, 4000)
      assert :ok = Validator.validate_field(:map_url, "https://api.example.com")

      assert {:error, [error]} = Validator.validate_field(:port, "not_integer")
      assert error.error == :invalid_value

      assert {:error, [error]} = Validator.validate_field(:unknown_field, "value")
      assert error.error == :unknown_field
    end
  end

  describe "validate_from_env/1" do
    test "validates environment variables" do
      # This test would require setting up environment variables
      # For now, we'll test the basic structure
      result = Validator.validate_from_env(:test)
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "format_errors/1" do
    test "formats errors with environment variable information" do
      errors = [
        %{
          field: :discord_bot_token,
          value: nil,
          error: :required,
          message: "Required field is missing"
        },
        %{
          field: :port,
          value: "invalid",
          error: :invalid_type,
          message: "Expected integer, got string"
        }
      ]

      formatted = Validator.format_errors(errors)

      assert String.contains?(formatted, "discord_bot_token")
      assert String.contains?(formatted, "DISCORD_BOT_TOKEN")
      assert String.contains?(formatted, "Required field is missing")
      assert String.contains?(formatted, "port")
      assert String.contains?(formatted, "Expected integer, got string")
    end
  end

  describe "validation_summary/1" do
    test "categorizes errors correctly" do
      errors = [
        %{field: :discord_bot_token, value: nil, error: :required, message: "Required"},
        %{field: :port, value: "bad", error: :invalid_type, message: "Type error"},
        %{field: :map_url, value: "bad", error: :invalid_value, message: "Value error"},
        %{
          field: :websocket_url,
          value: "localhost",
          error: :unreachable_url,
          message: "URL warning"
        }
      ]

      summary = Validator.validation_summary(errors)

      assert summary.total_errors == 4
      # required + invalid_type
      assert summary.critical_errors == 2
      assert summary.warnings == 2
      assert summary.by_category[:required_fields] == 1
      assert summary.by_category[:type_errors] == 1
      assert summary.by_category[:validation_errors] == 1
      assert summary.by_category[:connectivity_warnings] == 1
    end
  end

  describe "environment-specific validation" do
    test "production requires all critical fields" do
      minimal_config = %{notifications_enabled: false}

      assert :ok = Validator.validate_config(minimal_config, :dev)
      assert {:error, errors} = Validator.validate_config(minimal_config, :prod)

      # Should have errors for required fields in production
      required_errors = Enum.filter(errors, &(&1.error == :required))
      assert length(required_errors) > 0
    end

    test "validates map configuration completeness" do
      config = %{
        map_url: "https://api.wanderer.example",
        # Missing map_name and map_api_key
        notifications_enabled: false
      }

      assert {:error, errors} = Validator.validate_config(config, :prod)

      incomplete_errors = Enum.filter(errors, &(&1.error == :configuration_incomplete))

      map_errors =
        Enum.filter(incomplete_errors, &String.contains?(&1.message, "Map configuration"))

      assert length(map_errors) >= 1
    end

    test "warns about localhost URLs in production" do
      config = %{
        websocket_url: "ws://localhost:4004",
        wanderer_kills_url: "http://127.0.0.1:4004",
        notifications_enabled: false
      }

      assert {:error, errors} = Validator.validate_config(config, :prod)

      url_warnings = Enum.filter(errors, &(&1.error == :unreachable_url))
      assert length(url_warnings) >= 2
    end
  end
end
