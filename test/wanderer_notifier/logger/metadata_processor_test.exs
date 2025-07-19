defmodule WandererNotifier.Logger.MetadataProcessorTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Logger.MetadataProcessor

  describe "convert_to_keyword_list/1" do
    test "converts map to keyword list" do
      metadata = %{user_id: 123, action: "login"}
      result = MetadataProcessor.convert_to_keyword_list(metadata)

      assert is_list(result)
      assert result[:user_id] == 123
      assert result[:action] == "login"
      assert result[:_metadata_source] == "map"
    end

    test "preserves valid keyword list" do
      metadata = [user_id: 123, action: "login"]
      result = MetadataProcessor.convert_to_keyword_list(metadata)

      assert result[:user_id] == 123
      assert result[:action] == "login"
      assert result[:_metadata_source] == "keyword_list"
    end

    test "handles empty list" do
      result = MetadataProcessor.convert_to_keyword_list([])

      # Empty list is actually a valid keyword list in Elixir
      assert result[:_metadata_source] == "keyword_list"
    end

    test "handles invalid list" do
      # Not a keyword list
      metadata = [1, 2, 3]
      result = MetadataProcessor.convert_to_keyword_list(metadata)

      assert result[:_metadata_source] == "invalid_list_converted"
      assert result[:_metadata_warning] == "Non-keyword list converted to keyword list"
      assert result[:item_0] == 1
      assert result[:item_1] == 2
      assert result[:item_2] == 3
    end

    test "handles invalid type" do
      result = MetadataProcessor.convert_to_keyword_list("invalid")

      assert result[:_metadata_source] == "invalid_type"
      assert result[:_metadata_warning] == "Invalid metadata type converted to keyword list"
      assert result[:_original_type] == "string"
    end

    test "limits large invalid list to 10 items" do
      metadata = Enum.to_list(1..50)
      result = MetadataProcessor.convert_to_keyword_list(metadata)

      # Should only have items 0-9 plus metadata fields
      assert result[:item_0] == 1
      assert result[:item_9] == 10
      assert is_nil(result[:item_10])
    end
  end

  describe "prepare_metadata/2" do
    test "prepares metadata with category" do
      metadata = %{user_id: 123}
      result = MetadataProcessor.prepare_metadata(metadata, :api)

      assert result[:category] == :api
      assert result[:user_id] == 123
      assert result[:_metadata_source] == "map"
      assert result[:orig_metadata_type] == "map"
    end

    test "merges with Logger context" do
      # Set some Logger context
      Logger.metadata(existing_key: "existing_value")

      metadata = %{new_key: "new_value"}
      result = MetadataProcessor.prepare_metadata(metadata, :test)

      assert result[:category] == :test
      assert result[:new_key] == "new_value"
      assert result[:existing_key] == "existing_value"

      # Clean up
      Logger.metadata([])
    end

    test "category takes precedence over existing category" do
      Logger.metadata(category: :old_category)

      metadata = %{key: "value"}
      result = MetadataProcessor.prepare_metadata(metadata, :new_category)

      assert result[:category] == :new_category

      # Clean up
      Logger.metadata([])
    end
  end

  describe "format_debug_metadata/1" do
    test "formats metadata for debug output" do
      metadata = [user_id: 123, action: "login", category: :api]
      result = MetadataProcessor.format_debug_metadata(metadata)

      assert result =~ "user_id=123"
      assert result =~ "action=\"login\""
      assert result =~ "category=:api"
    end

    test "excludes internal metadata fields" do
      metadata = [
        user_id: 123,
        _metadata_source: "map",
        _metadata_warning: "warning",
        _original_data: "data",
        _caller: "caller",
        orig_metadata_type: "map"
      ]

      result = MetadataProcessor.format_debug_metadata(metadata)

      assert result =~ "user_id=123"
      refute result =~ "_metadata_source"
      refute result =~ "_metadata_warning"
      refute result =~ "_original_data"
      refute result =~ "_caller"
      refute result =~ "orig_metadata_type"
    end

    test "formats different value types" do
      metadata = [
        string_val: "test string",
        list_val: [1, 2, 3],
        map_val: %{a: 1, b: 2},
        atom_val: :test_atom,
        number_val: 42
      ]

      result = MetadataProcessor.format_debug_metadata(metadata)

      assert result =~ "string_val=\"test string\""
      assert result =~ "list_val=list[3]"
      assert result =~ "map_val=map{2}"
      assert result =~ "atom_val=:test_atom"
      assert result =~ "number_val=42"
    end

    test "truncates long strings" do
      long_string = String.duplicate("a", 200)
      metadata = [long_string: long_string]
      result = MetadataProcessor.format_debug_metadata(metadata)

      # Should be truncated to 100 characters plus quotes
      assert String.length(result) < 150
      assert result =~ "long_string=\""
      assert result =~ "aaa\""
    end

    test "returns empty string for empty metadata" do
      result = MetadataProcessor.format_debug_metadata([])
      assert result == ""
    end
  end

  describe "safe_to_atom/1" do
    test "preserves existing atoms" do
      assert MetadataProcessor.safe_to_atom(:existing_atom) == :existing_atom
    end

    test "converts existing atom strings" do
      assert MetadataProcessor.safe_to_atom("true") == true
      assert MetadataProcessor.safe_to_atom("false") == false
    end

    test "creates new atoms for known safe keys" do
      assert MetadataProcessor.safe_to_atom("_metadata_source") == :_metadata_source
      assert MetadataProcessor.safe_to_atom("_metadata_warning") == :_metadata_warning
    end

    test "creates safe atoms for unknown strings" do
      result = MetadataProcessor.safe_to_atom("unknown_key")
      assert is_atom(result)
      assert Atom.to_string(result) =~ "metadata_unknown_key"
    end

    test "handles non-string/non-atom keys" do
      result = MetadataProcessor.safe_to_atom(123)
      assert is_atom(result)
      assert Atom.to_string(result) =~ "metadata_123"
    end
  end

  describe "typeof/1" do
    test "identifies basic types" do
      assert MetadataProcessor.typeof("string") == "string"
      assert MetadataProcessor.typeof(true) == "boolean"
      assert MetadataProcessor.typeof(123) == "integer"
      assert MetadataProcessor.typeof(3.14) == "float"
      assert MetadataProcessor.typeof([1, 2, 3]) == "list"
      assert MetadataProcessor.typeof(%{a: 1}) == "map"
      assert MetadataProcessor.typeof({1, 2}) == "tuple"
      assert MetadataProcessor.typeof(:atom) == "atom"
      assert MetadataProcessor.typeof(self()) == "pid"
    end

    test "identifies functions" do
      fun = fn x -> x + 1 end
      assert MetadataProcessor.typeof(fun) == "function"
    end

    test "handles unknown types" do
      # Make a reference
      ref = make_ref()
      assert MetadataProcessor.typeof(ref) == "reference"
    end
  end

  describe "trace ID functions" do
    test "generate_trace_id/0 creates unique IDs" do
      id1 = MetadataProcessor.generate_trace_id()
      id2 = MetadataProcessor.generate_trace_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2
      # 8 bytes * 2 (hex encoding)
      assert String.length(id1) == 16
    end

    test "with_trace_id/1 adds trace ID and sets context" do
      metadata = [user_id: 123]
      trace_id = MetadataProcessor.with_trace_id(metadata)

      # Check that context was set
      current_metadata = Logger.metadata()
      assert current_metadata[:trace_id] == trace_id
      assert current_metadata[:user_id] == 123

      # Clean up
      Logger.metadata([])
    end

    test "with_trace_id/0 works with empty metadata" do
      trace_id = MetadataProcessor.with_trace_id()

      current_metadata = Logger.metadata()
      assert current_metadata[:trace_id] == trace_id

      # Clean up
      Logger.metadata([])
    end
  end

  describe "set_context/1" do
    test "sets Logger metadata context" do
      metadata = %{user_id: 123, session: "abc"}
      MetadataProcessor.set_context(metadata)

      current_metadata = Logger.metadata()
      assert current_metadata[:user_id] == 123
      assert current_metadata[:session] == "abc"

      # Clean up
      Logger.metadata([])
    end

    test "normalizes metadata before setting" do
      metadata = %{"string_key" => "value"}
      MetadataProcessor.set_context(metadata)

      current_metadata = Logger.metadata()
      # String key should be converted to atom
      assert current_metadata[:metadata_string_key] == "value" ||
               current_metadata[:string_key] == "value"

      # Clean up
      Logger.metadata([])
    end
  end
end
