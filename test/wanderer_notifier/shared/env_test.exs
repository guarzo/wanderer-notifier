defmodule WandererNotifier.Shared.EnvTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Shared.Env

  describe "get/2" do
    test "returns environment variable value when present" do
      System.put_env("TEST_VAR", "test_value")
      assert Env.get("TEST_VAR") == "test_value"
    end

    test "returns default when environment variable is missing" do
      assert Env.get("MISSING_VAR", "default") == "default"
    end

    test "returns nil when no default is provided and variable is missing" do
      assert Env.get("MISSING_VAR") == nil
    end
  end

  describe "get_required/1" do
    test "returns environment variable value when present" do
      System.put_env("REQUIRED_VAR", "required_value")
      assert Env.get_required("REQUIRED_VAR") == "required_value"
    end

    test "raises error when environment variable is missing" do
      assert_raise RuntimeError, "Missing required environment variable: MISSING_REQUIRED", fn ->
        Env.get_required("MISSING_REQUIRED")
      end
    end

    test "raises error when environment variable is empty" do
      System.put_env("EMPTY_REQUIRED", "")

      assert_raise RuntimeError, "Empty required environment variable: EMPTY_REQUIRED", fn ->
        Env.get_required("EMPTY_REQUIRED")
      end
    end
  end

  describe "get_boolean/2" do
    test "returns true for various true representations" do
      for value <- ["true", "1", "yes", "on"] do
        System.put_env("BOOL_VAR", value)
        assert Env.get_boolean("BOOL_VAR", false) == true
      end
    end

    test "returns false for various false representations" do
      for value <- ["false", "0", "no", "off"] do
        System.put_env("BOOL_VAR", value)
        assert Env.get_boolean("BOOL_VAR", true) == false
      end
    end

    test "returns default for invalid boolean values" do
      System.put_env("BOOL_VAR", "invalid")
      assert Env.get_boolean("BOOL_VAR", true) == true
      assert Env.get_boolean("BOOL_VAR", false) == false
    end

    test "returns default when variable is missing" do
      assert Env.get_boolean("MISSING_BOOL", true) == true
      assert Env.get_boolean("MISSING_BOOL", false) == false
    end
  end

  describe "get_integer/2" do
    test "returns integer value when valid" do
      System.put_env("INT_VAR", "42")
      assert Env.get_integer("INT_VAR", 0) == 42
    end

    test "returns default for invalid integer values" do
      System.put_env("INT_VAR", "not_a_number")
      assert Env.get_integer("INT_VAR", 100) == 100
    end

    test "returns default when variable is missing" do
      assert Env.get_integer("MISSING_INT", 200) == 200
    end
  end

  describe "get_float/2" do
    test "returns float value when valid" do
      System.put_env("FLOAT_VAR", "3.14")
      assert Env.get_float("FLOAT_VAR", 0.0) == 3.14
    end

    test "returns default for invalid float values" do
      System.put_env("FLOAT_VAR", "not_a_float")
      assert Env.get_float("FLOAT_VAR", 1.5) == 1.5
    end

    test "returns default when variable is missing" do
      assert Env.get_float("MISSING_FLOAT", 2.7) == 2.7
    end
  end

  describe "get_atom/2" do
    test "returns atom value when present and atom exists" do
      # Use an existing atom that we know exists
      System.put_env("ATOM_VAR", "info")
      assert Env.get_atom("ATOM_VAR", :default) == :info
    end

    test "returns default when variable is missing" do
      assert Env.get_atom("MISSING_ATOM", :default) == :default
    end

    test "returns default when atom does not exist" do
      System.put_env("ATOM_VAR", "non_existing_atom_that_definitely_does_not_exist")
      assert Env.get_atom("ATOM_VAR", :default) == :default
    end
  end

  describe "get_list/3" do
    test "returns list split by comma by default" do
      System.put_env("LIST_VAR", "item1,item2,item3")
      assert Env.get_list("LIST_VAR", []) == ["item1", "item2", "item3"]
    end

    test "returns list split by custom delimiter" do
      System.put_env("LIST_VAR", "item1|item2|item3")
      assert Env.get_list("LIST_VAR", [], "|") == ["item1", "item2", "item3"]
    end

    test "trims whitespace from items" do
      System.put_env("LIST_VAR", " item1 , item2 , item3 ")
      assert Env.get_list("LIST_VAR", []) == ["item1", "item2", "item3"]
    end

    test "returns default when variable is missing" do
      assert Env.get_list("MISSING_LIST", ["default"]) == ["default"]
    end

    test "returns default when variable is empty" do
      System.put_env("EMPTY_LIST", "")
      assert Env.get_list("EMPTY_LIST", ["default"]) == ["default"]
    end
  end

  describe "present?/1" do
    test "returns true when environment variable has value" do
      System.put_env("PRESENT_VAR", "some_value")
      assert Env.present?("PRESENT_VAR") == true
    end

    test "returns false when environment variable is missing" do
      assert Env.present?("MISSING_VAR") == false
    end

    test "returns false when environment variable is empty" do
      System.put_env("EMPTY_VAR", "")
      assert Env.present?("EMPTY_VAR") == false
    end
  end

  describe "get_app_config/4" do
    test "returns environment variable when present" do
      System.put_env("APP_CONFIG_VAR", "env_value")
      Application.put_env(:test_app, :test_key, "app_value")

      assert Env.get_app_config(:test_app, :test_key, "APP_CONFIG_VAR", "default") == "env_value"
    end

    test "returns app config when environment variable is missing" do
      Application.put_env(:test_app, :test_key, "app_value")

      assert Env.get_app_config(:test_app, :test_key, "MISSING_APP_VAR", "default") == "app_value"
    end

    test "returns default when both are missing" do
      assert Env.get_app_config(:test_app, :missing_key, "MISSING_APP_VAR", "default") ==
               "default"
    end
  end

  describe "get_prefixed/1" do
    test "returns map of variables with matching prefix" do
      System.put_env("PREFIX_VAR1", "value1")
      System.put_env("PREFIX_VAR2", "value2")
      System.put_env("OTHER_VAR", "other")

      result = Env.get_prefixed("PREFIX_")

      assert result["PREFIX_VAR1"] == "value1"
      assert result["PREFIX_VAR2"] == "value2"
      refute Map.has_key?(result, "OTHER_VAR")
    end
  end

  describe "validate_required/1" do
    test "returns :ok when all required variables are present" do
      System.put_env("REQ1", "value1")
      System.put_env("REQ2", "value2")

      assert Env.validate_required(["REQ1", "REQ2"]) == :ok
    end

    test "returns error with missing keys when some are missing" do
      System.put_env("REQ1", "value1")

      assert Env.validate_required(["REQ1", "MISSING1", "MISSING2"]) ==
               {:error, ["MISSING1", "MISSING2"]}
    end

    test "returns error when all required variables are missing" do
      assert Env.validate_required(["MISSING1", "MISSING2"]) == {:error, ["MISSING1", "MISSING2"]}
    end
  end
end
