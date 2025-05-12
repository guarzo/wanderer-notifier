defmodule WandererNotifier.Killmail.ContextTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Context

  test "creates a context with custom options" do
    context = Context.new(123, "Alice", :zkill_api, %{foo: :bar})

    assert %Context{} = context
    assert context.character_id == 123
    assert context.character_name == "Alice"
    assert context.source == :zkill_api
    assert context.options == %{foo: :bar}
  end

  test "creates a context with default options" do
    context = Context.new(123, "Alice", :zkill_api)

    assert context.character_id == 123
    assert context.character_name == "Alice"
    assert context.source == :zkill_api
    assert context.options == %{}
  end

  test "creates a context with custom source" do
    context = Context.new(456, "Bob", :zkill_websocket, %{baz: :qux})

    assert context.character_id == 456
    assert context.character_name == "Bob"
    assert context.source == :zkill_websocket
    assert context.options == %{baz: :qux}
  end

  test "creates a context with default source" do
    context = Context.new(456, "Bob", :zkill_websocket)

    assert context.character_id == 456
    assert context.character_name == "Bob"
    assert context.source == :zkill_websocket
    assert context.options == %{}
  end

  test "Access behavior implementation" do
    ctx = Context.new(42, "test", :zkill_api, %{test: true})

    # Test fetch
    assert {:ok, 42} = Access.fetch(ctx, :character_id)
    assert :error = Access.fetch(ctx, :not_a_field)

    # Test get via Access protocol
    assert Access.get(ctx, :character_id) == 42
    assert Access.get(ctx, :not_a_field) == nil
    assert Access.get(ctx, :not_a_field, :default) == :default

    # Test get_and_update
    {old, new} = Access.get_and_update(ctx, :character_id, fn current -> {current, 99} end)
    assert old == 42
    assert new.character_id == 99

    # Test pop
    {val, new_ctx} = Access.pop(ctx, :character_id)
    assert val == 42
    assert new_ctx.character_id == nil

    # Test direct access via dot notation
    assert ctx.mode == %{mode: :default}

    # Test realtime? function
    assert Context.realtime?(ctx) == true
  end
end
