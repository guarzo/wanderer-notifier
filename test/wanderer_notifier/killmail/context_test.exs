defmodule WandererNotifier.Killmail.ContextTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Context

  describe "new_historical/5" do
    test "creates a context struct for historical processing" do
      context = Context.new_historical(123, "Alice", :zkill_api, "batch-1", %{foo: :bar})
      assert %Context{} = context
      assert context.character_id == 123
      assert context.character_name == "Alice"
      assert context.source == :zkill_api
      assert context.batch_id == "batch-1"
      assert context.options == %{foo: :bar}
      assert context.mode.mode == :historical
    end

    test "defaults options to empty map if not provided" do
      context = Context.new_historical(123, "Alice", :zkill_api, "batch-1")
      assert context.options == %{}
    end
  end

  describe "new_realtime/4" do
    test "creates a context struct for realtime processing" do
      context = Context.new_realtime(456, "Bob", :zkill_websocket, %{baz: :qux})
      assert %Context{} = context
      assert context.character_id == 456
      assert context.character_name == "Bob"
      assert context.source == :zkill_websocket
      assert context.batch_id == nil
      assert context.options == %{baz: :qux}
      assert context.mode.mode == :realtime
    end

    test "defaults options to empty map if not provided" do
      context = Context.new_realtime(456, "Bob", :zkill_websocket)
      assert context.options == %{}
    end
  end

  describe "historical?/1 and realtime?/1" do
    test "returns true for historical context, false for realtime" do
      hist = Context.new_historical(1, "A", :zkill_api, "b")
      real = Context.new_realtime(2, "B", :zkill_websocket)
      assert Context.historical?(hist)
      refute Context.historical?(real)
      refute Context.realtime?(hist)
      assert Context.realtime?(real)
    end

    test "returns false for non-context structs" do
      refute Context.historical?(%{})
      refute Context.realtime?(%{})
      refute Context.historical?(nil)
      refute Context.realtime?(nil)
    end
  end
end
