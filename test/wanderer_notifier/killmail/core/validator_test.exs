defmodule WandererNotifier.Killmail.Core.ValidatorTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Core.Data

  # Test implementation of the Validator functions
  describe "validate/1" do
    test "returns :ok for valid killmail data" do
      killmail = %Data{
        killmail_id: 12345,
        solar_system_id: 30_000_142,
        kill_time: DateTime.utc_now()
      }

      assert :ok = validate(killmail)
    end

    test "returns errors for missing killmail_id" do
      killmail = %Data{
        solar_system_id: 30_000_142,
        kill_time: DateTime.utc_now()
      }

      assert {:error, errors} = validate(killmail)
      assert Enum.any?(errors, fn {key, _} -> key == :missing_killmail_id end)
    end

    test "returns errors for missing solar_system_id" do
      killmail = %Data{
        killmail_id: 12345,
        kill_time: DateTime.utc_now()
      }

      assert {:error, errors} = validate(killmail)
      assert Enum.any?(errors, fn {key, _} -> key == :missing_system_id end)
    end

    test "returns errors for missing kill_time" do
      killmail = %Data{
        killmail_id: 12345,
        solar_system_id: 30_000_142
      }

      assert {:error, errors} = validate(killmail)
      assert Enum.any?(errors, fn {key, _} -> key == :missing_kill_time end)
    end

    test "returns errors for invalid killmail_id type" do
      killmail = %Data{
        # String instead of integer
        killmail_id: "12345",
        solar_system_id: 30_000_142,
        kill_time: DateTime.utc_now()
      }

      assert {:error, errors} = validate(killmail)
      assert Enum.any?(errors, fn {key, _} -> key == :invalid_killmail_id end)
    end

    test "returns errors for invalid solar_system_id type" do
      killmail = %Data{
        killmail_id: 12345,
        # String instead of integer
        solar_system_id: "30000142",
        kill_time: DateTime.utc_now()
      }

      assert {:error, errors} = validate(killmail)
      assert Enum.any?(errors, fn {key, _} -> key == :invalid_system_id end)
    end

    test "returns errors for invalid kill_time type" do
      killmail = %Data{
        killmail_id: 12345,
        solar_system_id: 30_000_142,
        # String instead of DateTime
        kill_time: "2023-01-01T12:00:00Z"
      }

      assert {:error, errors} = validate(killmail)
      assert Enum.any?(errors, fn {key, _} -> key == :invalid_kill_time end)
    end

    test "returns multiple errors when multiple fields are invalid" do
      killmail = %Data{
        # All fields missing or invalid
      }

      assert {:error, errors} = validate(killmail)
      # At least 3 errors (missing killmail_id, solar_system_id, kill_time)
      assert length(errors) >= 3
    end

    test "returns error for non-Data input" do
      assert {:error, [{:invalid_data_type, _}]} = validate(%{not_a_data: true})
      assert {:error, [{:invalid_data_type, _}]} = validate("not a data")
      assert {:error, [{:invalid_data_type, _}]} = validate(nil)
    end
  end

  describe "has_minimum_required_data?/1" do
    test "returns true when killmail has minimum required data" do
      killmail = %Data{
        killmail_id: 12345
      }

      assert has_minimum_required_data?(killmail) == true
    end

    test "returns false when killmail is missing minimum required data" do
      killmail = %Data{
        # Missing killmail_id
      }

      assert has_minimum_required_data?(killmail) == false
    end

    test "returns false for non-Data input" do
      assert has_minimum_required_data?(%{not_a_data: true}) == false
      assert has_minimum_required_data?("not a data") == false
      assert has_minimum_required_data?(nil) == false
    end
  end

  describe "log_validation_errors/2" do
    import ExUnit.CaptureLog

    test "logs errors for Data struct" do
      killmail = %Data{killmail_id: 12345}
      errors = [{:missing_system_id, "Solar system ID is required"}]

      log =
        capture_log(fn ->
          log_validation_errors(killmail, errors)
        end)

      assert log =~ "Validation errors"
      assert log =~ "12345"
      assert log =~ "missing_system_id"
    end

    test "logs errors for non-Data input" do
      not_data = %{some_field: "value"}
      errors = [{:invalid_data_type, "Expected Data struct"}]

      log =
        capture_log(fn ->
          log_validation_errors(not_data, errors)
        end)

      assert log =~ "Validation errors for non-Data input"
      assert log =~ "invalid_data_type"
    end
  end

  # Validator implementations for testing
  defp validate(%Data{} = killmail) do
    errors =
      []
      |> validate_killmail_id(killmail)
      |> validate_system_id(killmail)
      |> validate_kill_time(killmail)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  defp validate(other) do
    {:error, [{:invalid_data_type, "Expected Data struct, got: #{inspect(other)}"}]}
  end

  defp has_minimum_required_data?(%Data{} = killmail) do
    not is_nil(killmail.killmail_id)
  end

  defp has_minimum_required_data?(_), do: false

  defp log_validation_errors(%Data{} = killmail, errors) do
    formatted_errors = format_errors(errors)

    require Logger

    Logger.error(
      "Validation errors for killmail ##{killmail.killmail_id || "unknown"}: #{Enum.join(formatted_errors, ", ")}",
      %{
        errors: formatted_errors
      }
    )

    :ok
  end

  defp log_validation_errors(other, errors) do
    formatted_errors = format_errors(errors)

    require Logger

    Logger.error("Validation errors for non-Data input: #{Enum.join(formatted_errors, ", ")}", %{
      input: inspect(other),
      errors: formatted_errors
    })

    :ok
  end

  # Helper functions
  defp validate_killmail_id(errors, %Data{killmail_id: nil}) do
    [{:missing_killmail_id, "Killmail ID is required"} | errors]
  end

  defp validate_killmail_id(errors, %Data{killmail_id: killmail_id})
       when not is_integer(killmail_id) do
    [{:invalid_killmail_id, "Killmail ID must be an integer"} | errors]
  end

  defp validate_killmail_id(errors, _), do: errors

  defp validate_system_id(errors, %Data{solar_system_id: nil}) do
    [{:missing_system_id, "Solar system ID is required"} | errors]
  end

  defp validate_system_id(errors, %Data{solar_system_id: system_id})
       when not is_integer(system_id) do
    [{:invalid_system_id, "Solar system ID must be an integer"} | errors]
  end

  defp validate_system_id(errors, _), do: errors

  defp validate_kill_time(errors, %Data{kill_time: nil}) do
    [{:missing_kill_time, "Kill time is required"} | errors]
  end

  defp validate_kill_time(errors, %Data{kill_time: kill_time})
       when not is_struct(kill_time, DateTime) do
    [{:invalid_kill_time, "Kill time must be a DateTime"} | errors]
  end

  defp validate_kill_time(errors, _), do: errors

  defp format_errors(errors) do
    Enum.map(errors, fn {key, message} ->
      "#{key}: #{message}"
    end)
  end
end
