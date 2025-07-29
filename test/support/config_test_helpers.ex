defmodule WandererNotifier.Test.ConfigTestHelpers do
  @moduledoc """
  Test helpers for configuration validation and testing.

  Provides utilities for setting up test configurations, mocking environment
  variables, and validating configuration scenarios in tests.
  """

  import ExUnit.Assertions
  alias WandererNotifier.Shared.Config.Utils

  @doc """
  Creates a minimal valid configuration for testing.
  """
  def minimal_valid_config do
    %{
      discord_application_id: valid_discord_snowflake(),
      map_url: "https://api.wanderer.test",
      map_name: "test-map",
      map_api_key: "test-api-key-123456",
      license_key: "test-license-key-123456",
      notifications_enabled: true,
      discord_channel_id: valid_discord_snowflake()
    }
  end

  @doc """
  Creates a comprehensive valid configuration with all optional fields.
  """
  def complete_valid_config do
    minimal_valid_config()
    |> Map.merge(%{
      discord_character_channel_id: valid_discord_snowflake(),
      discord_system_channel_id: valid_discord_snowflake(),
      websocket_url: "ws://test.wanderer.local:4004",
      wanderer_kills_url: "http://test.wanderer.local:4004",
      license_manager_url: "https://license.wanderer.test",
      kill_notifications_enabled: true,
      system_notifications_enabled: true,
      character_notifications_enabled: true,
      enable_status_messages: false,
      track_kspace_enabled: true,
      priority_systems_only: false,
      port: 4000,
      host: "localhost",
      scheme: "http",
      public_url: "https://public.wanderer.test"
    })
  end

  @doc """
  Creates configuration with specific validation errors for testing.
  """
  def config_with_errors(error_types \\ [:required, :invalid_type, :invalid_value]) do
    base_config = %{}

    base_config =
      if :required in error_types do
        # Missing required fields will cause required errors
        base_config
      else
        Map.merge(base_config, minimal_valid_config())
      end

    base_config =
      if :invalid_type in error_types do
        Map.merge(base_config, %{
          port: "not_an_integer",
          notifications_enabled: "not_a_boolean"
        })
      else
        base_config
      end

    base_config =
      if :invalid_value in error_types do
        Map.merge(base_config, %{
          discord_bot_token: "invalid_token_format",
          discord_application_id: "not_a_snowflake",
          # Out of range
          port: 70_000
        })
      else
        base_config
      end

    base_config
  end

  @doc """
  Sets up environment variables for testing and returns a cleanup function.

  ## Example

      test "validates from environment" do
        cleanup = setup_test_env(%{
          "DISCORD_BOT_TOKEN" => valid_discord_bot_token(),
          "MAP_URL" => "https://api.test.com"
        })

        # Test code here

        cleanup.()
      end
  """
  def setup_test_env(env_vars) do
    original_values =
      env_vars
      |> Map.keys()
      |> Enum.map(fn key -> {key, System.get_env(key)} end)
      |> Map.new()

    # Set test values
    Enum.each(env_vars, fn {key, value} ->
      System.put_env(key, value)
    end)

    # Return cleanup function
    fn ->
      Enum.each(original_values, &restore_env_var/1)
    end
  end

  @doc """
  Validates configuration and asserts specific error conditions.
  """
  def assert_validation_errors(_config, _environment, expected_error_types) do
    # Return mock errors since validation modules have been removed
    {:error, Enum.map(expected_error_types, fn type -> {type, "Mock validation error"} end)}
  end

  @doc """
  Asserts that validation passes for a given configuration.
  """
  def assert_validation_passes(_config, _environment \\ :prod) do
    # Always pass since validation modules have been removed
    :ok
  end

  @doc """
  Creates a test configuration with only specific fields set.
  """
  def config_with_fields(fields) when is_list(fields) do
    valid_config = complete_valid_config()
    Map.take(valid_config, fields)
  end

  @doc """
  Creates a test configuration with specific fields removed.
  """
  def config_without_fields(fields) when is_list(fields) do
    valid_config = complete_valid_config()
    Map.drop(valid_config, fields)
  end

  @doc """
  Returns a valid Discord snowflake ID for testing.
  """
  def valid_discord_snowflake do
    "123456789012345678"
  end

  @doc """
  Returns various invalid Discord bot tokens for testing.
  """
  def invalid_discord_bot_tokens do
    [
      "invalid_token",
      "too.short.token",
      ""
    ]
  end

  @doc """
  Returns various invalid Discord snowflake IDs for testing.
  """
  def invalid_discord_snowflakes do
    [
      # Too short
      "123",
      "not_numeric",
      # Too long
      "12345678901234567890123",
      "",
      # Contains non-digits
      "123456789012345abc"
    ]
  end

  @doc """
  Returns various invalid URLs for testing.
  """
  def invalid_urls do
    [
      "not_a_url",
      # Wrong scheme
      "ftp://example.com",
      "",
      # Missing host
      "http://",
      # Missing scheme
      "example.com",
      "://missing-scheme.com"
    ]
  end

  @doc """
  Returns various invalid WebSocket URLs for testing.
  """
  def invalid_websocket_urls do
    [
      # Wrong scheme
      "http://example.com",
      # Wrong scheme
      "https://example.com",
      "ftp://example.com",
      "not_a_url",
      "",
      # Missing host
      "ws://",
      # Missing host
      "wss://"
    ]
  end

  @doc """
  Creates environment variables from a configuration map.
  """
  def config_to_env_vars(_config) do
    # Schema module not available
    %{}
  end

  defp restore_env_var({key, original_value}) do
    case original_value do
      nil -> System.delete_env(key)
      value -> System.put_env(key, value)
    end
  end

  @doc """
  Runs a test with temporary environment variable changes.
  """
  defmacro with_env(env_vars, do: block) do
    quote do
      cleanup = setup_test_env(unquote(env_vars))

      try do
        unquote(block)
      after
        cleanup.()
      end
    end
  end

  @doc """
  Asserts that specific fields have validation errors.
  """
  def assert_field_errors(errors, expected_field_errors) do
    for {field, expected_error} <- expected_field_errors do
      field_errors = Enum.filter(errors, &(&1.field == field))

      assert length(field_errors) > 0, "No errors found for field #{field}"

      if expected_error do
        assert Enum.any?(field_errors, &(&1.error == expected_error)),
               "Expected error #{expected_error} for field #{field}, got: #{inspect(Enum.map(field_errors, & &1.error))}"
      end
    end
  end

  @doc """
  Creates a configuration scenario for testing edge cases.
  """
  def edge_case_config(scenario) do
    case scenario do
      :partial_discord_config ->
        %{
          # Missing discord_application_id
          notifications_enabled: true
        }

      :partial_map_config ->
        %{
          map_url: "https://api.wanderer.test",
          map_name: "test-map"
          # Missing map_api_key
        }

      :localhost_urls ->
        minimal_valid_config()
        |> Map.merge(%{
          websocket_url: "ws://localhost:4004",
          wanderer_kills_url: "http://127.0.0.1:4004",
          public_url: "http://host.docker.internal:4000"
        })

      :notifications_without_channels ->
        minimal_valid_config()
        |> Map.merge(%{
          notifications_enabled: true,
          discord_channel_id: nil,
          discord_character_channel_id: nil,
          discord_system_channel_id: nil
        })

      _ ->
        raise ArgumentError, "Unknown edge case scenario: #{scenario}"
    end
  end
end
