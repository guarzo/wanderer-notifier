defmodule WandererNotifier.Killmail.Core.ContextTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Core.{Context, Mode}

  describe "new_historical/5" do
    test "creates a new historical context with the specified values" do
      character_id = 12345
      character_name = "Test Character"
      source = :zkill
      batch_id = "batch-123"
      options = %{metadata: %{test: true}}

      context = Context.new_historical(character_id, character_name, source, batch_id, options)

      assert context.character_id == character_id
      assert context.character_name == character_name
      assert context.source == source
      assert context.batch_id == batch_id
      assert context.metadata == %{test: true}
      assert %Mode{} = context.mode
      assert context.mode.mode == :historical
    end

    test "creates a new historical context with default values" do
      context = Context.new_historical(nil, nil, :unknown, nil)

      assert context.character_id == nil
      assert context.character_name == nil
      assert context.source == :unknown
      assert context.batch_id == nil
      assert context.metadata == %{}
      assert %Mode{} = context.mode
      assert context.mode.mode == :historical
    end

    test "passes mode options to Mode.new" do
      options = %{mode_options: %{custom_option: "value"}}

      context = Context.new_historical(nil, nil, :unknown, nil, options)

      assert context.mode.options[:custom_option] == "value"
    end
  end

  describe "new_realtime/4" do
    test "creates a new realtime context with the specified values" do
      character_id = 12345
      character_name = "Test Character"
      source = :websocket
      options = %{metadata: %{test: true}}

      context = Context.new_realtime(character_id, character_name, source, options)

      assert context.character_id == character_id
      assert context.character_name == character_name
      assert context.source == source
      assert context.batch_id == nil # Realtime doesn't use batch_id
      assert context.metadata == %{test: true}
      assert %Mode{} = context.mode
      assert context.mode.mode == :realtime
    end

    test "creates a new realtime context with default values" do
      context = Context.new_realtime(nil, nil, :unknown)

      assert context.character_id == nil
      assert context.character_name == nil
      assert context.source == :unknown
      assert context.batch_id == nil
      assert context.metadata == %{}
      assert %Mode{} = context.mode
      assert context.mode.mode == :realtime
    end

    test "passes mode options to Mode.new" do
      options = %{mode_options: %{custom_option: "value"}}

      context = Context.new_realtime(nil, nil, :unknown, options)

      assert context.mode.options[:custom_option] == "value"
    end
  end

  describe "historical?/1" do
    test "returns true for historical context" do
      context = Context.new_historical(nil, nil, :unknown, nil)
      assert Context.historical?(context) == true
    end

    test "returns false for non-historical context" do
      context = Context.new_realtime(nil, nil, :unknown)
      assert Context.historical?(context) == false
    end

    test "returns false for invalid input" do
      assert Context.historical?(nil) == false
      assert Context.historical?(%{}) == false
      assert Context.historical?("not a context") == false
    end
  end

  describe "realtime?/1" do
    test "returns true for realtime context" do
      context = Context.new_realtime(nil, nil, :unknown)
      assert Context.realtime?(context) == true
    end

    test "returns false for non-realtime context" do
      context = Context.new_historical(nil, nil, :unknown, nil)
      assert Context.realtime?(context) == false
    end

    test "returns false for invalid input" do
      assert Context.realtime?(nil) == false
      assert Context.realtime?(%{}) == false
      assert Context.realtime?("not a context") == false
    end
  end
end
