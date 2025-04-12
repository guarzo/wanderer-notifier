defmodule WandererNotifier.Killmail.Core.ModeTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Core.Mode

  describe "new/2" do
    test "creates a new mode struct with the specified mode" do
      mode = Mode.new(:realtime)

      assert %Mode{} = mode
      assert mode.mode == :realtime
    end

    test "creates a new mode struct with custom options" do
      options = %{custom_option: "value"}
      mode = Mode.new(:historical, options)

      assert mode.mode == :historical
      assert mode.options[:custom_option] == "value"
    end

    test "merges custom options with default options" do
      options = %{notify: false} # Override default
      mode = Mode.new(:realtime, options)

      # Default options for realtime should include persist: true
      assert mode.options[:persist] == true
      # But our custom option should override the default
      assert mode.options[:notify] == false
    end

    test "creates a new mode struct with unknown mode" do
      mode = Mode.new(:custom_mode)

      assert mode.mode == :custom_mode
      # Should use fallback default options
      assert mode.options[:persist] == true
      assert mode.options[:notify] == false
    end
  end

  describe "default_options/1" do
    test "returns realtime default options" do
      options = Mode.default_options(:realtime)

      assert options[:persist] == true
      assert options[:notify] == true
      assert options[:cache] == true
    end

    test "returns historical default options" do
      options = Mode.default_options(:historical)

      assert options[:persist] == true
      assert options[:notify] == false
      assert options[:cache] == true
    end

    test "returns manual default options" do
      options = Mode.default_options(:manual)

      assert options[:persist] == true
      assert options[:notify] == true
      assert options[:cache] == true
    end

    test "returns batch default options" do
      options = Mode.default_options(:batch)

      assert options[:persist] == true
      assert options[:notify] == false
      assert options[:cache] == true
    end

    test "returns fallback default options for unknown mode" do
      options = Mode.default_options(:custom_mode)

      assert options[:persist] == true
      assert options[:notify] == false
      assert options[:cache] == true
    end
  end
end
