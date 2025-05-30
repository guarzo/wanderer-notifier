defmodule WandererNotifier.Killmail.ContextTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Context

  test "creates a context with custom options" do
    context = Context.new("123", "Alice", %{source: :zkill_api, foo: :bar})

    assert %Context{} = context
    assert context.killmail_id == "123"
    assert context.system_name == "Alice"
    assert context.options == %{source: :zkill_api, foo: :bar}
  end

  test "creates a context with default options" do
    context = Context.new("123", "Alice")

    assert context.killmail_id == "123"
    assert context.system_name == "Alice"
    assert context.options == %{}
  end

  test "creates a context with custom source in options" do
    context = Context.new("456", "Bob", %{source: :zkill_redisq, baz: :qux})

    assert context.kill_id == "456"
    assert context.kill_hash == "Bob"
    assert context.options == %{source: :zkill_redisq, baz: :qux}
  end

  test "creates a context with default source in options" do
    context = Context.new("456", "Bob", %{source: :zkill_redisq})

    assert context.kill_id == "456"
    assert context.kill_hash == "Bob"
    assert context.options == %{source: :zkill_redisq}
  end

  test "Access behavior implementation" do
    ctx = Context.new("42", "test", %{source: :zkill_api, test: true})

    # Test fetch
    assert {:ok, "42"} = Access.fetch(ctx, :killmail_id)
    assert :error = Access.fetch(ctx, :not_a_field)

    # Test get via Access protocol
    assert Access.get(ctx, :killmail_id) == "42"
    assert Access.get(ctx, :not_a_field) == nil
    assert Access.get(ctx, :not_a_field, :default) == :default

    # Test get_and_update
    {old, new} = Access.get_and_update(ctx, :killmail_id, fn current -> {current, "99"} end)
    assert old == "42"
    assert new.killmail_id == "99"

    # Test pop
    {val, new_ctx} = Access.pop(ctx, :killmail_id)
    assert val == "42"
    assert new_ctx.killmail_id == nil
  end
end
