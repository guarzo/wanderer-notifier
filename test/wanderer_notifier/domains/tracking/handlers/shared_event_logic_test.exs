defmodule WandererNotifier.Domains.Tracking.Handlers.SharedEventLogicTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Handlers.SharedEventLogic

  import ExUnit.CaptureLog

  describe "handle_entity_event/6" do
    test "successfully processes entity event" do
      event = %{
        "payload" => %{
          "name" => "Test Entity",
          "id" => "123"
        }
      }

      extract_fn = fn payload ->
        {:ok, %{name: payload["name"], id: payload["id"]}}
      end

      cache_fn = fn _entity -> :ok end
      notify_fn = fn _entity -> :ok end

      log_output =
        capture_log(fn ->
          result =
            SharedEventLogic.handle_entity_event(
              event,
              "test-map",
              :entity_added,
              extract_fn,
              cache_fn,
              notify_fn
            )

          assert result == :ok
        end)

      assert log_output =~ "entity_added payload received"
      assert log_output =~ "Processing entity_added event"
      assert log_output =~ "entity_added processed successfully"
    end

    test "handles extraction errors" do
      event = %{
        "payload" => %{
          "invalid" => "data"
        }
      }

      extract_fn = fn _payload ->
        {:error, :invalid_data}
      end

      cache_fn = fn _entity -> :ok end
      notify_fn = fn _entity -> :ok end

      log_output =
        capture_log(fn ->
          result =
            SharedEventLogic.handle_entity_event(
              event,
              "test-map",
              :entity_added,
              extract_fn,
              cache_fn,
              notify_fn
            )

          assert result == {:error, :invalid_data}
        end)

      assert log_output =~ "Failed to process entity_added event"
    end

    test "handles cache errors" do
      event = %{
        "payload" => %{
          "name" => "Test Entity",
          "id" => "123"
        }
      }

      extract_fn = fn payload ->
        {:ok, %{name: payload["name"], id: payload["id"]}}
      end

      cache_fn = fn _entity -> {:error, :cache_failure} end
      notify_fn = fn _entity -> :ok end

      log_output =
        capture_log(fn ->
          result =
            SharedEventLogic.handle_entity_event(
              event,
              "test-map",
              :entity_added,
              extract_fn,
              cache_fn,
              notify_fn
            )

          assert result == {:error, :cache_failure}
        end)

      assert log_output =~ "Failed to process entity_added event"
      # The error reason is logged as metadata, not in the message itself
    end

    test "handles notification errors" do
      event = %{
        "payload" => %{
          "name" => "Test Entity",
          "id" => "123"
        }
      }

      extract_fn = fn payload ->
        {:ok, %{name: payload["name"], id: payload["id"]}}
      end

      cache_fn = fn _entity -> :ok end
      notify_fn = fn _entity -> {:error, :notification_failure} end

      log_output =
        capture_log(fn ->
          result =
            SharedEventLogic.handle_entity_event(
              event,
              "test-map",
              :entity_added,
              extract_fn,
              cache_fn,
              notify_fn
            )

          assert result == {:error, :notification_failure}
        end)

      assert log_output =~ "Failed to process entity_added event"
      # The error reason is logged as metadata, not in the message itself
    end

    test "handles missing payload" do
      event = %{}

      extract_fn = fn payload ->
        {:ok, %{name: payload["name"], id: payload["id"]}}
      end

      cache_fn = fn _entity -> :ok end
      notify_fn = fn _entity -> :ok end

      log_output =
        capture_log(fn ->
          result =
            SharedEventLogic.handle_entity_event(
              event,
              "test-map",
              :entity_added,
              extract_fn,
              cache_fn,
              notify_fn
            )

          assert result == :ok
        end)

      assert log_output =~ "entity_added payload received"
      assert log_output =~ "entity_added processed successfully"
    end
  end

  describe "extract_entity_name/1" do
    test "extracts name from payload" do
      payload = %{"name" => "Test Entity"}
      assert SharedEventLogic.extract_entity_name(payload) == "Test Entity"
    end

    test "extracts character_name from payload" do
      payload = %{"character_name" => "Test Character"}
      assert SharedEventLogic.extract_entity_name(payload) == "Test Character"
    end

    test "extracts system_name from payload" do
      payload = %{"system_name" => "Test System"}
      assert SharedEventLogic.extract_entity_name(payload) == "Test System"
    end

    test "prefers name over other options" do
      payload = %{
        "name" => "Primary Name",
        "character_name" => "Character Name",
        "system_name" => "System Name"
      }

      assert SharedEventLogic.extract_entity_name(payload) == "Primary Name"
    end

    test "returns nil when no name fields found" do
      payload = %{"id" => "123"}
      assert SharedEventLogic.extract_entity_name(payload) == nil
    end
  end

  describe "extract_entity_id/1" do
    test "extracts id from payload" do
      payload = %{"id" => "123"}
      assert SharedEventLogic.extract_entity_id(payload) == "123"
    end

    test "extracts character_eve_id from payload" do
      payload = %{"character_eve_id" => "456"}
      assert SharedEventLogic.extract_entity_id(payload) == "456"
    end

    test "extracts eve_id from payload" do
      payload = %{"eve_id" => "789"}
      assert SharedEventLogic.extract_entity_id(payload) == "789"
    end

    test "extracts character_id from payload" do
      payload = %{"character_id" => "101112"}
      assert SharedEventLogic.extract_entity_id(payload) == "101112"
    end

    test "extracts solar_system_id from payload" do
      payload = %{"solar_system_id" => 30_000_142}
      assert SharedEventLogic.extract_entity_id(payload) == 30_000_142
    end

    test "extracts system_id from payload" do
      payload = %{"system_id" => 30_000_142}
      assert SharedEventLogic.extract_entity_id(payload) == 30_000_142
    end

    test "prefers id over other options" do
      payload = %{
        "id" => "primary",
        "character_eve_id" => "secondary",
        "solar_system_id" => 123_456
      }

      assert SharedEventLogic.extract_entity_id(payload) == "primary"
    end

    test "returns nil when no id fields found" do
      payload = %{"name" => "Test"}
      assert SharedEventLogic.extract_entity_id(payload) == nil
    end
  end

  describe "extract_entity_name_from_result/1" do
    test "extracts name from struct with atom key" do
      entity = %{name: "Test Entity"}
      assert SharedEventLogic.extract_entity_name_from_result(entity) == "Test Entity"
    end

    test "extracts name from map with string key" do
      entity = %{"name" => "Test Entity"}
      assert SharedEventLogic.extract_entity_name_from_result(entity) == "Test Entity"
    end

    test "returns nil for entity without name" do
      entity = %{id: "123"}
      assert SharedEventLogic.extract_entity_name_from_result(entity) == nil
    end

    test "returns nil for invalid entity" do
      assert SharedEventLogic.extract_entity_name_from_result(nil) == nil
      assert SharedEventLogic.extract_entity_name_from_result("string") == nil
    end
  end

  describe "extract_entity_id_from_result/1" do
    test "extracts eve_id from struct" do
      entity = %{eve_id: "123456"}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == "123456"
    end

    test "extracts eve_id from map with string key" do
      entity = %{"eve_id" => "123456"}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == "123456"
    end

    test "extracts solar_system_id from struct" do
      entity = %{solar_system_id: 30_000_142}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == 30_000_142
    end

    test "extracts solar_system_id from map with string key" do
      entity = %{"solar_system_id" => 30_000_142}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == 30_000_142
    end

    test "extracts id from struct" do
      entity = %{id: "abc123"}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == "abc123"
    end

    test "extracts id from map with string key" do
      entity = %{"id" => "abc123"}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == "abc123"
    end

    test "prefers eve_id over other options" do
      entity = %{
        eve_id: "primary",
        solar_system_id: 123_456,
        id: "fallback"
      }

      assert SharedEventLogic.extract_entity_id_from_result(entity) == "primary"
    end

    test "returns nil for entity without id fields" do
      entity = %{name: "Test"}
      assert SharedEventLogic.extract_entity_id_from_result(entity) == nil
    end
  end

  describe "no_op_notification/0" do
    test "creates function that returns :ok" do
      no_op_fn = SharedEventLogic.no_op_notification()
      assert is_function(no_op_fn, 1)
      assert no_op_fn.("any_entity") == :ok
    end
  end

  describe "log_only_notification/1" do
    test "creates function that logs and returns :ok" do
      log_fn = SharedEventLogic.log_only_notification("Test action performed")
      assert is_function(log_fn, 1)

      entity = %{name: "Test Entity", eve_id: "123456"}

      log_output =
        capture_log(fn ->
          result = log_fn.(entity)
          assert result == :ok
        end)

      assert log_output =~ "Test action performed"
      # Note: In test environment, metadata may not be included in log output
      # The function calls AppLogger.api_info with metadata, but capture_log
      # may not capture the metadata fields
    end

    test "handles entities without name or id" do
      log_fn = SharedEventLogic.log_only_notification("Action without entity info")
      entity = %{other_field: "value"}

      log_output =
        capture_log(fn ->
          result = log_fn.(entity)
          assert result == :ok
        end)

      assert log_output =~ "Action without entity info"
    end
  end

  describe "safe_operation/1" do
    test "wraps successful operation" do
      operation = fn _entity -> :ok end
      safe_op = SharedEventLogic.safe_operation(operation)

      assert safe_op.("test") == :ok
    end

    test "wraps operation that returns {:ok, result}" do
      operation = fn _entity -> {:ok, "success"} end
      safe_op = SharedEventLogic.safe_operation(operation)

      assert safe_op.("test") == :ok
    end

    test "passes through error tuples" do
      operation = fn _entity -> {:error, :custom_error} end
      safe_op = SharedEventLogic.safe_operation(operation)

      assert safe_op.("test") == {:error, :custom_error}
    end

    test "handles unexpected return values" do
      operation = fn _entity -> "unexpected" end
      safe_op = SharedEventLogic.safe_operation(operation)

      assert {:error, {:unexpected_result, "unexpected"}} = safe_op.("test")
    end

    test "catches and wraps exceptions" do
      operation = fn _entity -> raise "Something went wrong" end
      safe_op = SharedEventLogic.safe_operation(operation)

      assert {:error, {:operation_failed, %RuntimeError{}}} = safe_op.("test")
    end
  end

  describe "conditional_notification/2" do
    test "calls notification function when condition is true" do
      condition_fn = fn _entity -> true end
      notification_fn = fn entity -> {:ok, "notified #{entity}"} end

      conditional_fn = SharedEventLogic.conditional_notification(condition_fn, notification_fn)

      assert {:ok, "notified test"} = conditional_fn.("test")
    end

    test "skips notification when condition is false" do
      condition_fn = fn _entity -> false end
      notification_fn = fn _entity -> {:error, "should not be called"} end

      conditional_fn = SharedEventLogic.conditional_notification(condition_fn, notification_fn)

      assert conditional_fn.("test") == :ok
    end

    test "handles notification errors when condition is true" do
      condition_fn = fn _entity -> true end
      notification_fn = fn _entity -> {:error, :notification_failed} end

      conditional_fn = SharedEventLogic.conditional_notification(condition_fn, notification_fn)

      assert {:error, :notification_failed} = conditional_fn.("test")
    end

    test "works with complex conditions" do
      # Only notify for entities with eve_id
      condition_fn = fn entity ->
        Map.has_key?(entity, :eve_id) && entity.eve_id != nil
      end

      notification_fn = fn entity -> {:ok, "Character #{entity.eve_id} notified"} end

      conditional_fn = SharedEventLogic.conditional_notification(condition_fn, notification_fn)

      # Should notify when eve_id is present
      entity_with_id = %{eve_id: "123456", name: "Test Character"}
      assert {:ok, "Character 123456 notified"} = conditional_fn.(entity_with_id)

      # Should not notify when eve_id is missing
      entity_without_id = %{name: "Test Character"}
      assert conditional_fn.(entity_without_id) == :ok

      # Should not notify when eve_id is nil
      entity_with_nil_id = %{eve_id: nil, name: "Test Character"}
      assert conditional_fn.(entity_with_nil_id) == :ok
    end
  end
end
