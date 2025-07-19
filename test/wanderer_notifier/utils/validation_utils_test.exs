defmodule WandererNotifier.Utils.ValidationUtilsTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Utils.ValidationUtils

  describe "valid_type?/2" do
    test "validates string types correctly" do
      assert ValidationUtils.valid_type?("hello", :string)
      refute ValidationUtils.valid_type?(123, :string)
      refute ValidationUtils.valid_type?(nil, :string)
    end

    test "validates integer types correctly" do
      assert ValidationUtils.valid_type?(42, :integer)
      refute ValidationUtils.valid_type?(3.14, :integer)
      refute ValidationUtils.valid_type?("42", :integer)
    end

    test "validates float types correctly" do
      assert ValidationUtils.valid_type?(3.14, :float)
      refute ValidationUtils.valid_type?(42, :float)
      refute ValidationUtils.valid_type?("3.14", :float)
    end

    test "validates number types correctly" do
      assert ValidationUtils.valid_type?(42, :number)
      assert ValidationUtils.valid_type?(3.14, :number)
      refute ValidationUtils.valid_type?("42", :number)
    end

    test "validates boolean types correctly" do
      assert ValidationUtils.valid_type?(true, :boolean)
      assert ValidationUtils.valid_type?(false, :boolean)
      refute ValidationUtils.valid_type?("true", :boolean)
      refute ValidationUtils.valid_type?(1, :boolean)
    end

    test "validates map types correctly" do
      assert ValidationUtils.valid_type?(%{}, :map)
      assert ValidationUtils.valid_type?(%{"key" => "value"}, :map)
      refute ValidationUtils.valid_type?([], :map)
      refute ValidationUtils.valid_type?("map", :map)
    end

    test "validates list types correctly" do
      assert ValidationUtils.valid_type?([], :list)
      assert ValidationUtils.valid_type?([1, 2, 3], :list)
      refute ValidationUtils.valid_type?(%{}, :list)
      refute ValidationUtils.valid_type?("list", :list)
    end

    test "validates atom types correctly" do
      assert ValidationUtils.valid_type?(:atom, :atom)
      assert ValidationUtils.valid_type?(:test, :atom)
      refute ValidationUtils.valid_type?("atom", :atom)
      refute ValidationUtils.valid_type?(123, :atom)
    end

    test "validates any types correctly" do
      assert ValidationUtils.valid_type?("anything", :any)
      assert ValidationUtils.valid_type?(123, :any)
      assert ValidationUtils.valid_type?(nil, :any)
      assert ValidationUtils.valid_type?(%{}, :any)
    end

    test "rejects unknown types" do
      refute ValidationUtils.valid_type?("test", :unknown)
      refute ValidationUtils.valid_type?(123, :invalid)
    end
  end

  describe "validate_required_fields/2" do
    test "passes when all required fields are present" do
      data = %{"name" => "test", "id" => 1, "active" => true}
      result = ValidationUtils.validate_required_fields(data, ["name", "id"])

      assert {:ok, ^data} = result
    end

    test "fails when required fields are missing" do
      data = %{"name" => "test"}
      result = ValidationUtils.validate_required_fields(data, ["name", "id", "active"])

      assert {:error, {:missing_fields, ["id", "active"]}} = result
    end

    test "fails when required fields are empty strings" do
      data = %{"name" => "", "id" => 1}
      result = ValidationUtils.validate_required_fields(data, ["name", "id"])

      assert {:error, {:empty_fields, ["name"]}} = result
    end

    test "handles mixed field types (string and atom keys)" do
      data = %{"name" => "test", "id" => 1}
      result = ValidationUtils.validate_required_fields(data, [:name, "id"])

      assert {:ok, ^data} = result
    end

    test "prioritizes missing fields over empty fields in error reporting" do
      data = %{"name" => ""}
      result = ValidationUtils.validate_required_fields(data, ["name", "id"])

      assert {:error, {:missing_fields, ["id"]}} = result
    end
  end

  describe "validate_optional_field/2" do
    test "accepts nil values for any type" do
      assert {:ok, nil} = ValidationUtils.validate_optional_field(nil, :string)
      assert {:ok, nil} = ValidationUtils.validate_optional_field(nil, :integer)
      assert {:ok, nil} = ValidationUtils.validate_optional_field(nil, :boolean)
    end

    test "validates present values according to type" do
      assert {:ok, "test"} = ValidationUtils.validate_optional_field("test", :string)
      assert {:ok, 42} = ValidationUtils.validate_optional_field(42, :integer)
      assert {:ok, true} = ValidationUtils.validate_optional_field(true, :boolean)
    end

    test "rejects present values with wrong type" do
      assert {:error, :invalid_type} = ValidationUtils.validate_optional_field("test", :integer)
      assert {:error, :invalid_type} = ValidationUtils.validate_optional_field(42, :string)
      assert {:error, :invalid_type} = ValidationUtils.validate_optional_field("true", :boolean)
    end
  end

  describe "valid_non_empty_map?/1" do
    test "returns true for non-empty maps" do
      assert ValidationUtils.valid_non_empty_map?(%{"key" => "value"})
      assert ValidationUtils.valid_non_empty_map?(%{a: 1, b: 2})
    end

    test "returns false for empty maps" do
      refute ValidationUtils.valid_non_empty_map?(%{})
    end

    test "returns false for non-maps" do
      refute ValidationUtils.valid_non_empty_map?("not a map")
      refute ValidationUtils.valid_non_empty_map?([])
      refute ValidationUtils.valid_non_empty_map?(nil)
      refute ValidationUtils.valid_non_empty_map?(123)
    end
  end

  describe "validate_map_structure/2" do
    test "validates correct map structure" do
      schema = %{name: :string, id: :integer, active: :boolean}
      data = %{"name" => "test", "id" => 1, "active" => true}

      assert {:ok, ^data} = ValidationUtils.validate_map_structure(data, schema)
    end

    test "reports type errors" do
      schema = %{name: :string, id: :integer}
      data = %{"name" => "test", "id" => "not_integer"}

      assert {:error, {:type_errors, [{"id", :integer, "not_integer"}]}} =
               ValidationUtils.validate_map_structure(data, schema)
    end

    test "reports multiple type errors" do
      schema = %{name: :string, id: :integer, active: :boolean}
      data = %{"name" => 123, "id" => "not_integer", "active" => "not_boolean"}

      assert {:error, {:type_errors, errors}} =
               ValidationUtils.validate_map_structure(data, schema)

      assert length(errors) == 3
      assert {"name", :string, 123} in errors
      assert {"id", :integer, "not_integer"} in errors
      assert {"active", :boolean, "not_boolean"} in errors
    end

    test "ignores missing fields (handled by required field validation)" do
      schema = %{name: :string, id: :integer}
      # missing "id"
      data = %{"name" => "test"}

      assert {:ok, ^data} = ValidationUtils.validate_map_structure(data, schema)
    end

    test "handles mixed atom/string schema keys" do
      schema = %{"name" => :string, :id => :integer}
      data = %{"name" => "test", "id" => 1}

      assert {:ok, ^data} = ValidationUtils.validate_map_structure(data, schema)
    end
  end

  describe "validate_data_structure/3" do
    test "validates complete data structure successfully" do
      schema = %{name: :string, id: :integer}
      required = ["name", "id"]
      data = %{"name" => "test", "id" => 1}

      assert {:ok, ^data} = ValidationUtils.validate_data_structure(data, schema, required)
    end

    test "fails on missing required fields" do
      schema = %{name: :string, id: :integer}
      required = ["name", "id"]
      data = %{"name" => "test"}

      assert {:error, {:missing_fields, ["id"]}} =
               ValidationUtils.validate_data_structure(data, schema, required)
    end

    test "fails on type errors" do
      schema = %{name: :string, id: :integer}
      required = ["name", "id"]
      data = %{"name" => "test", "id" => "not_integer"}

      assert {:error, {:type_errors, [{"id", :integer, "not_integer"}]}} =
               ValidationUtils.validate_data_structure(data, schema, required)
    end
  end

  describe "validate_has_any_key/2" do
    test "passes when at least one key is present" do
      data = %{"name" => "test", "other" => "value"}

      assert {:ok, ^data} = ValidationUtils.validate_has_any_key(data, ["name", "id"])
      assert {:ok, ^data} = ValidationUtils.validate_has_any_key(data, ["id", "name"])
    end

    test "fails when no keys are present" do
      data = %{"other" => "value"}

      assert {:error, {:missing_any_key, ["name", "id"]}} =
               ValidationUtils.validate_has_any_key(data, ["name", "id"])
    end

    test "handles mixed atom/string keys" do
      data = %{"name" => "test"}

      assert {:ok, ^data} = ValidationUtils.validate_has_any_key(data, [:name, "id"])
    end
  end

  describe "validate_list/2" do
    test "validates list of valid items" do
      items = [1, 2, 3, 4, 5]

      assert {:ok, ^items} = ValidationUtils.validate_list(items, &is_integer/1)
    end

    test "reports invalid items by index" do
      items = [1, "2", 3, "4", 5]

      assert {:error, {:invalid_items, [1, 3]}} =
               ValidationUtils.validate_list(items, &is_integer/1)
    end

    test "validates empty list" do
      assert {:ok, []} = ValidationUtils.validate_list([], &is_integer/1)
    end

    test "works with custom validation functions" do
      items = ["test", "valid", "strings"]
      validator = fn item -> is_binary(item) and String.length(item) > 2 end

      assert {:ok, ^items} = ValidationUtils.validate_list(items, validator)
    end
  end

  describe "valid_optional_string_field?/1" do
    test "accepts nil values" do
      assert ValidationUtils.valid_optional_string_field?(nil)
    end

    test "accepts non-empty strings" do
      assert ValidationUtils.valid_optional_string_field?("valid")
      assert ValidationUtils.valid_optional_string_field?("test string")
    end

    test "rejects empty strings" do
      refute ValidationUtils.valid_optional_string_field?("")
    end

    test "rejects non-string values" do
      refute ValidationUtils.valid_optional_string_field?(123)
      refute ValidationUtils.valid_optional_string_field?(%{})
      refute ValidationUtils.valid_optional_string_field?([])
      refute ValidationUtils.valid_optional_string_field?(true)
    end
  end

  describe "format_validation_error/1" do
    test "formats missing fields errors" do
      error = {:missing_fields, ["name", "id"]}
      result = ValidationUtils.format_validation_error(error)

      assert result == "Missing required fields: name, id"
    end

    test "formats empty fields errors" do
      error = {:empty_fields, ["name"]}
      result = ValidationUtils.format_validation_error(error)

      assert result == "Empty required fields: name"
    end

    test "formats type errors" do
      error = {:type_errors, [{"id", :integer, "string_value"}]}
      result = ValidationUtils.format_validation_error(error)

      assert result == "Type errors: id (expected integer, got string)"
    end

    test "formats missing any key errors" do
      error = {:missing_any_key, ["eve_id", "character_eve_id"]}
      result = ValidationUtils.format_validation_error(error)

      assert result == "Must have at least one of: eve_id, character_eve_id"
    end

    test "formats invalid items errors" do
      error = {:invalid_items, [1, 3, 5]}
      result = ValidationUtils.format_validation_error(error)

      assert result == "Invalid items at positions: 1, 3, 5"
    end

    test "formats simple invalid type errors" do
      error = :invalid_type
      result = ValidationUtils.format_validation_error(error)

      assert result == "Invalid type for field"
    end

    test "formats unknown errors" do
      error = :unknown_error
      result = ValidationUtils.format_validation_error(error)

      assert result == "Validation error: :unknown_error"
    end
  end

  describe "type_name/1" do
    test "returns correct type names" do
      assert ValidationUtils.type_name("string") == "string"
      assert ValidationUtils.type_name(42) == "integer"
      assert ValidationUtils.type_name(3.14) == "float"
      assert ValidationUtils.type_name(true) == "boolean"
      assert ValidationUtils.type_name(%{}) == "map"
      assert ValidationUtils.type_name([]) == "list"
      assert ValidationUtils.type_name(:atom) == "atom"
    end

    test "returns unknown for unrecognized types" do
      # This is mainly for edge cases or exotic types
      assert ValidationUtils.type_name(make_ref()) == "unknown"
    end
  end

  describe "validate_system_data/1" do
    setup do
      valid_system = %{
        "name" => "Test System",
        "id" => "123",
        "solar_system_id" => 30_000_142,
        "locked" => false,
        "visible" => true,
        "position_x" => 100,
        "position_y" => 200,
        "status" => 1
      }

      {:ok, valid_system: valid_system}
    end

    test "validates complete system data", %{valid_system: system} do
      assert {:ok, ^system} = ValidationUtils.validate_system_data(system)
    end

    test "validates system data with optional fields", %{valid_system: system} do
      system_with_optional =
        Map.merge(system, %{
          "custom_name" => "Custom Name",
          "description" => "System description",
          "tag" => "important"
        })

      assert {:ok, ^system_with_optional} =
               ValidationUtils.validate_system_data(system_with_optional)
    end

    test "allows nil optional fields", %{valid_system: system} do
      system_with_nils =
        Map.merge(system, %{
          "custom_name" => nil,
          "description" => nil
        })

      assert {:ok, ^system_with_nils} = ValidationUtils.validate_system_data(system_with_nils)
    end

    test "fails with missing required fields", %{valid_system: system} do
      incomplete_system = Map.delete(system, "name")

      assert {:error, {:missing_fields, ["name"]}} =
               ValidationUtils.validate_system_data(incomplete_system)
    end

    test "fails with wrong types", %{valid_system: system} do
      bad_system = Map.put(system, "solar_system_id", "not_integer")

      assert {:error, {:type_errors, [{"solar_system_id", :integer, "not_integer"}]}} =
               ValidationUtils.validate_system_data(bad_system)
    end

    test "fails with empty optional string fields", %{valid_system: system} do
      bad_system = Map.put(system, "custom_name", "")

      assert {:error, {:invalid_optional_fields, ["custom_name"]}} =
               ValidationUtils.validate_system_data(bad_system)
    end

    test "fails for non-map input" do
      assert {:error, :not_a_map} = ValidationUtils.validate_system_data("not a map")
      assert {:error, :not_a_map} = ValidationUtils.validate_system_data(nil)
      assert {:error, :not_a_map} = ValidationUtils.validate_system_data(123)
    end
  end

  describe "validate_character_data/1" do
    test "validates character with eve_id" do
      character = %{"eve_id" => 123_456, "name" => "Character Name"}

      assert {:ok, ^character} = ValidationUtils.validate_character_data(character)
    end

    test "validates character with character_eve_id" do
      character = %{"character_eve_id" => 123_456, "name" => "Character Name"}

      assert {:ok, ^character} = ValidationUtils.validate_character_data(character)
    end

    test "fails when no eve_id fields are present" do
      character = %{"name" => "Character Name", "other_field" => "value"}

      assert {:error, {:missing_any_key, ["eve_id", "character_eve_id"]}} =
               ValidationUtils.validate_character_data(character)
    end

    test "fails when name is missing" do
      character = %{"eve_id" => 123_456}

      assert {:error, {:missing_fields, ["name"]}} =
               ValidationUtils.validate_character_data(character)
    end

    test "fails for non-map input" do
      assert {:error, :not_a_map} = ValidationUtils.validate_character_data("not a map")
      assert {:error, :not_a_map} = ValidationUtils.validate_character_data(nil)
    end
  end

  describe "validate_killmail_data/1" do
    test "validates killmail with killmail_id" do
      killmail = %{"killmail_id" => 12345, "other_data" => "value"}

      assert {:ok, ^killmail} = ValidationUtils.validate_killmail_data(killmail)
    end

    test "validates killmail with victim" do
      killmail = %{"victim" => %{"character_id" => 123}, "other_data" => "value"}

      assert {:ok, ^killmail} = ValidationUtils.validate_killmail_data(killmail)
    end

    test "fails when neither required key is present" do
      killmail = %{"other_data" => "value"}

      assert {:error, {:missing_any_key, ["killmail_id", "victim"]}} =
               ValidationUtils.validate_killmail_data(killmail)
    end

    test "fails for non-map input" do
      assert {:error, :not_a_map} = ValidationUtils.validate_killmail_data("not a map")
      assert {:error, :not_a_map} = ValidationUtils.validate_killmail_data(nil)
    end
  end
end
