defmodule WandererNotifier.Data.MapUtilTest do
  use ExUnit.Case

  alias WandererNotifier.Data.MapUtil

  describe "get_value/2" do
    test "gets value with string key" do
      map = %{"name" => "John", "age" => 30}
      assert MapUtil.get_value(map, ["name"]) == "John"
      assert MapUtil.get_value(map, ["age"]) == 30
    end

    test "gets value with atom key" do
      map = %{name: "John", age: 30}
      assert MapUtil.get_value(map, [:name]) == "John"
      assert MapUtil.get_value(map, [:age]) == 30
    end

    test "tries multiple keys until it finds a match" do
      map = %{"user_id" => 123}
      assert MapUtil.get_value(map, ["id", "user_id", :id, :user_id]) == 123

      map = %{user_id: 456}
      assert MapUtil.get_value(map, ["id", "user_id", :id, :user_id]) == 456
    end

    test "returns nil when no keys match" do
      map = %{"foo" => "bar"}
      assert MapUtil.get_value(map, ["name", :name]) == nil
    end

    test "handles empty map" do
      assert MapUtil.get_value(%{}, ["name", :name]) == nil
    end
  end

  describe "extract_to_struct/3" do
    defmodule TestStruct do
      defstruct [:name, :age, :location]
    end

    test "extracts values into a struct using specified mappings" do
      map = %{"name" => "john", "user_age" => 30, "city" => "New York"}
      mappings = [name: ["name"], age: ["user_age"], location: ["city"]]

      result = MapUtil.extract_to_struct(map, TestStruct, mappings)

      assert %TestStruct{name: "john", age: 30, location: "New York"} = result
    end

    test "returns default values when keys are not found" do
      map = %{"user_age" => 30}
      mappings = [name: ["name"], age: ["user_age"], location: ["city"]]

      result = MapUtil.extract_to_struct(map, TestStruct, mappings)

      assert %TestStruct{name: nil, age: 30, location: nil} = result
    end
  end

  describe "extract_map/2" do
    test "extracts values into a map using mappings" do
      map = %{
        "name" => "John",
        "years" => 30,
        "email_address" => "john@example.com"
      }

      mappings = [
        {:name, ["name", :name]},
        {:age, ["age", "years", :age, :years]},
        {:email, ["email", "email_address", :email, :email_address]}
      ]

      result = MapUtil.extract_map(map, mappings)

      assert is_map(result)
      assert result.name == "John"
      assert result.age == 30
      assert result.email == "john@example.com"
    end

    test "uses default values when keys are not found" do
      map = %{"name" => "John"}

      mappings = [
        {:name, ["name"]},
        {:age, ["age"], 0},
        {:email, ["email"], "no-email@example.com"}
      ]

      result = MapUtil.extract_map(map, mappings)

      assert is_map(result)
      assert result.name == "John"
      assert result.age == 0
      assert result.email == "no-email@example.com"
    end
  end

  describe "atomize_keys/2" do
    test "converts string keys to atom keys" do
      map = %{"name" => "John", "age" => 30}
      result = MapUtil.atomize_keys(map)

      assert result == %{name: "John", age: 30}
    end

    test "keeps existing atom keys" do
      map = %{"name" => "John", age: 30}
      result = MapUtil.atomize_keys(map)

      assert result == %{name: "John", age: 30}
    end

    test "recursively converts nested maps when option is set" do
      map = %{
        "user" => %{
          "name" => "John",
          "address" => %{"city" => "New York"}
        }
      }

      result = MapUtil.atomize_keys(map, recursive: true)

      assert result == %{
               user: %{
                 name: "John",
                 address: %{city: "New York"}
               }
             }
    end

    test "does not recursively convert by default" do
      map = %{
        "user" => %{
          "name" => "John"
        }
      }

      result = MapUtil.atomize_keys(map)

      assert result == %{
               user: %{
                 "name" => "John"
               }
             }
    end
  end
end
