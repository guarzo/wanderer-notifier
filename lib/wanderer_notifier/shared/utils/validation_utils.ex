defmodule WandererNotifier.Shared.Utils.ValidationUtils do
  @moduledoc """
  Unified validation utilities for consistent data validation across the application.

  This module consolidates validation patterns found throughout the codebase,
  eliminating duplication and providing a consistent API for validation tasks.

  ## Usage Examples

      # Type validation
      iex> ValidationUtils.valid_type?("string", :string)
      true

      # Required field validation
      iex> ValidationUtils.validate_required_fields(%{"name" => "test"}, ["name", "id"])
      {:error, {:missing_fields, ["id"]}}

      # Map structure validation
      iex> ValidationUtils.valid_map_structure?(%{"id" => 1}, %{id: :integer})
      {:ok, %{"id" => 1}}
  """

  @doc """
  Validates the type of a value against an expected type.

  ## Supported Types
  - `:string` - Binary values
  - `:integer` - Integer values
  - `:float` - Float values
  - `:number` - Any numeric value (integer or float)
  - `:boolean` - Boolean values
  - `:map` - Map values
  - `:list` - List values
  - `:atom` - Atom values
  - `:any` - Any value (always returns true)

  ## Examples
      iex> valid_type?("hello", :string)
      true

      iex> valid_type?(42, :integer)
      true

      iex> valid_type?(3.14, :number)
      true

      iex> valid_type?("hello", :integer)
      false
  """
  @spec valid_type?(any(), atom()) :: boolean()
  def valid_type?(value, :string), do: is_binary(value)
  def valid_type?(value, :integer), do: is_integer(value)
  def valid_type?(value, :float), do: is_float(value)
  def valid_type?(value, :number), do: is_number(value)
  def valid_type?(value, :boolean), do: is_boolean(value)
  def valid_type?(value, :map), do: is_map(value)
  def valid_type?(value, :list), do: is_list(value)
  def valid_type?(value, :atom), do: is_atom(value)
  def valid_type?(_, :any), do: true
  def valid_type?(_, _), do: false

  @doc """
  Validates that required fields are present in a map.

  ## Examples
      iex> validate_required_fields(%{"name" => "test", "id" => 1}, ["name", "id"])
      {:ok, %{"name" => "test", "id" => 1}}

      iex> validate_required_fields(%{"name" => "test"}, ["name", "id"])
      {:error, {:missing_fields, ["id"]}}

      iex> validate_required_fields(%{"name" => ""}, ["name"])
      {:error, {:empty_fields, ["name"]}}
  """
  @spec validate_required_fields(map(), [String.t() | atom()]) ::
          {:ok, map()} | {:error, {:missing_fields | :empty_fields, [String.t()]}}
  def validate_required_fields(data, fields) when is_map(data) and is_list(fields) do
    string_fields = Enum.map(fields, &to_string/1)

    {missing, empty} = categorize_field_errors(data, string_fields)

    build_validation_result(data, missing, empty)
  end

  defp categorize_field_errors(data, fields) do
    Enum.reduce(fields, {[], []}, fn field, {missing_acc, empty_acc} ->
      categorize_field_value(data, field, missing_acc, empty_acc)
    end)
  end

  defp categorize_field_value(data, field, missing_acc, empty_acc) do
    case Map.get(data, field) do
      nil -> {[field | missing_acc], empty_acc}
      "" -> {missing_acc, [field | empty_acc]}
      _value -> {missing_acc, empty_acc}
    end
  end

  defp build_validation_result(data, [], []), do: {:ok, data}

  defp build_validation_result(_data, missing, []) when missing != [],
    do: {:error, {:missing_fields, Enum.reverse(missing)}}

  defp build_validation_result(_data, _missing, empty) when empty != [],
    do: {:error, {:empty_fields, Enum.reverse(empty)}}

  @doc """
  Validates optional fields, allowing nil values but checking type when present.

  ## Examples
      iex> validate_optional_field(nil, :string)
      {:ok, nil}

      iex> validate_optional_field("valid", :string)
      {:ok, "valid"}

      iex> validate_optional_field(123, :string)
      {:error, :invalid_type}
  """
  @spec validate_optional_field(any(), atom()) :: {:ok, any()} | {:error, :invalid_type}
  def validate_optional_field(nil, _type), do: {:ok, nil}

  def validate_optional_field(value, type) do
    if valid_type?(value, type) do
      {:ok, value}
    else
      {:error, :invalid_type}
    end
  end

  @doc """
  Validates that a value is a non-empty map.

  ## Examples
      iex> valid_non_empty_map?(%{"key" => "value"})
      true

      iex> valid_non_empty_map?(%{})
      false

      iex> valid_non_empty_map?("not a map")
      false
  """
  @spec valid_non_empty_map?(any()) :: boolean()
  def valid_non_empty_map?(value) do
    is_map(value) and map_size(value) > 0
  end

  @doc """
  Validates a map against a schema defining required field types.

  ## Examples
      iex> schema = %{name: :string, id: :integer, active: :boolean}
      iex> data = %{"name" => "test", "id" => 1, "active" => true}
      iex> validate_map_structure(data, schema)
      {:ok, %{"name" => "test", "id" => 1, "active" => true}}

      iex> bad_data = %{"name" => "test", "id" => "not_integer"}
      iex> validate_map_structure(bad_data, schema)
      {:error, {:type_errors, [{"id", :integer, "not_integer"}]}}
  """
  @spec validate_map_structure(map(), map()) ::
          {:ok, map()} | {:error, {:type_errors, [{String.t(), atom(), any()}]}}
  def validate_map_structure(data, schema) when is_map(data) and is_map(schema) do
    type_errors = collect_type_errors(data, schema)
    format_validation_result(data, type_errors)
  end

  defp collect_type_errors(data, schema) do
    Enum.reduce(schema, [], fn {field, expected_type}, acc ->
      validate_field_type(data, field, expected_type, acc)
    end)
  end

  defp validate_field_type(data, field, expected_type, acc) do
    field_str = to_string(field)

    case Map.get(data, field_str) do
      # Missing fields handled by validate_required_fields
      nil -> acc
      value -> check_type_and_accumulate(value, expected_type, field_str, acc)
    end
  end

  defp check_type_and_accumulate(value, expected_type, field_str, acc) do
    if valid_type?(value, expected_type) do
      acc
    else
      [{field_str, expected_type, value} | acc]
    end
  end

  defp format_validation_result(data, []), do: {:ok, data}
  defp format_validation_result(_data, errors), do: {:error, {:type_errors, Enum.reverse(errors)}}

  @doc """
  Validates a full data structure with both required fields and type checking.

  Combines required field validation and type validation in a single call.

  ## Examples
      iex> schema = %{name: :string, id: :integer}
      iex> required = ["name", "id"]
      iex> data = %{"name" => "test", "id" => 1}
      iex> validate_data_structure(data, schema, required)
      {:ok, %{"name" => "test", "id" => 1}}
  """
  @spec validate_data_structure(map(), map(), [String.t() | atom()]) ::
          {:ok, map()} | {:error, term()}
  def validate_data_structure(data, schema, required_fields) do
    with {:ok, _} <- validate_required_fields(data, required_fields),
         {:ok, validated} <- validate_map_structure(data, schema) do
      {:ok, validated}
    end
  end

  @doc """
  Validates that a map contains at least one of the specified keys.

  ## Examples
      iex> validate_has_any_key(%{"name" => "test"}, ["name", "id"])
      {:ok, %{"name" => "test"}}

      iex> validate_has_any_key(%{"other" => "value"}, ["name", "id"])
      {:error, {:missing_any_key, ["name", "id"]}}
  """
  @spec validate_has_any_key(map(), [String.t() | atom()]) ::
          {:ok, map()} | {:error, {:missing_any_key, [String.t()]}}
  def validate_has_any_key(data, keys) when is_map(data) and is_list(keys) do
    string_keys = Enum.map(keys, &to_string/1)

    has_any_key = Enum.any?(string_keys, fn key -> Map.has_key?(data, key) end)

    if has_any_key do
      {:ok, data}
    else
      {:error, {:missing_any_key, string_keys}}
    end
  end

  @doc """
  Validates that all items in a list pass a validation function.

  ## Examples
      iex> validate_list([1, 2, 3], &is_integer/1)
      {:ok, [1, 2, 3]}

      iex> validate_list([1, "2", 3], &is_integer/1)
      {:error, {:invalid_items, [1]}}  # Index 1 ("2") failed validation
  """
  @spec validate_list(list(), (any() -> boolean())) ::
          {:ok, list()} | {:error, {:invalid_items, [non_neg_integer()]}}
  def validate_list(items, validator_fn) when is_list(items) and is_function(validator_fn, 1) do
    invalid_indices =
      items
      |> Enum.with_index()
      |> Enum.reduce([], fn {item, index}, acc ->
        if validator_fn.(item) do
          acc
        else
          [index | acc]
        end
      end)
      |> Enum.reverse()

    case invalid_indices do
      [] -> {:ok, items}
      indices -> {:error, {:invalid_items, indices}}
    end
  end

  @doc """
  Validates that a string field is either nil or a non-empty string.

  Useful for optional string fields that should not be empty if provided.

  ## Examples
      iex> valid_optional_string_field?(nil)
      true

      iex> valid_optional_string_field?("valid string")
      true

      iex> valid_optional_string_field?("")
      false

      iex> valid_optional_string_field?(123)
      false
  """
  @spec valid_optional_string_field?(any()) :: boolean()
  def valid_optional_string_field?(nil), do: true
  def valid_optional_string_field?(value) when is_binary(value), do: value != ""
  def valid_optional_string_field?(_), do: false

  @doc """
  Formats validation errors into human-readable messages.

  ## Examples
      iex> format_validation_error({:missing_fields, ["name", "id"]})
      "Missing required fields: name, id"

      iex> format_validation_error({:type_errors, [{"id", :integer, "string"}]})
      "Type errors: id (expected integer, got string)"
  """
  @spec format_validation_error(term()) :: String.t()
  def format_validation_error({:missing_fields, fields}) do
    "Missing required fields: #{Enum.join(fields, ", ")}"
  end

  def format_validation_error({:empty_fields, fields}) do
    "Empty required fields: #{Enum.join(fields, ", ")}"
  end

  def format_validation_error({:type_errors, errors}) do
    error_messages =
      Enum.map(errors, fn {field, expected, actual} ->
        actual_type = type_name(actual)
        "#{field} (expected #{expected}, got #{actual_type})"
      end)

    "Type errors: #{Enum.join(error_messages, ", ")}"
  end

  def format_validation_error({:missing_any_key, keys}) do
    "Must have at least one of: #{Enum.join(keys, ", ")}"
  end

  def format_validation_error({:invalid_items, indices}) do
    "Invalid items at positions: #{Enum.join(indices, ", ")}"
  end

  def format_validation_error(:invalid_type) do
    "Invalid type for field"
  end

  def format_validation_error(error) do
    "Validation error: #{inspect(error)}"
  end

  @doc """
  Returns a human-readable name for a value's type.

  ## Examples
      iex> type_name("string")
      "string"

      iex> type_name(42)
      "integer"

      iex> type_name(%{})
      "map"
  """
  @spec type_name(any()) :: String.t()
  def type_name(value) when is_binary(value), do: "string"
  def type_name(value) when is_integer(value), do: "integer"
  def type_name(value) when is_float(value), do: "float"
  def type_name(value) when is_boolean(value), do: "boolean"
  def type_name(value) when is_map(value), do: "map"
  def type_name(value) when is_list(value), do: "list"
  def type_name(value) when is_atom(value), do: "atom"
  def type_name(_), do: "unknown"

  # Convenience functions for common validation patterns

  @doc """
  Validates a system data structure (for SystemsClient).

  ## Examples
      iex> system = %{
      ...>   "name" => "system1", "id" => "123", "solar_system_id" => 30000142,
      ...>   "locked" => false, "visible" => true, "position_x" => 100,
      ...>   "position_y" => 200, "status" => 1
      ...> }
      iex> validate_system_data(system)
      {:ok, system}
  """
  @spec validate_system_data(map()) :: {:ok, map()} | {:error, term()}
  def validate_system_data(data) when is_map(data) do
    required_fields = [
      "name",
      "id",
      "solar_system_id",
      "locked",
      "visible",
      "position_x",
      "position_y",
      "status"
    ]

    schema = %{
      name: :string,
      id: :string,
      solar_system_id: :integer,
      locked: :boolean,
      visible: :boolean,
      position_x: :integer,
      position_y: :integer,
      status: :integer,
      # Optional fields
      custom_name: :string,
      description: :string,
      original_name: :string,
      temporary_name: :string,
      tag: :string
    }

    with {:ok, _} <- validate_required_fields(data, required_fields),
         {:ok, validated} <- validate_map_structure(data, schema) do
      # Additional validation for optional string fields
      optional_fields = ["custom_name", "description", "original_name", "temporary_name", "tag"]

      optional_validation_errors =
        Enum.filter(optional_fields, fn field ->
          case Map.get(data, field) do
            nil -> false
            value -> not valid_optional_string_field?(value)
          end
        end)

      case optional_validation_errors do
        [] -> {:ok, validated}
        invalid_fields -> {:error, {:invalid_optional_fields, invalid_fields}}
      end
    end
  end

  def validate_system_data(_), do: {:error, :not_a_map}

  @doc """
  Validates a character data structure (for CharactersClient).

  ## Examples
      iex> character = %{"eve_id" => 123456, "name" => "Character Name"}
      iex> validate_character_data(character)
      {:ok, character}

      iex> character_alt = %{"character_eve_id" => 123456, "name" => "Character Name"}
      iex> validate_character_data(character_alt)
      {:ok, character_alt}
  """
  @spec validate_character_data(map()) :: {:ok, map()} | {:error, term()}
  def validate_character_data(data) when is_map(data) do
    # Characters might have either "eve_id" or "character_eve_id"
    eve_id_keys = ["eve_id", "character_eve_id"]
    required_fields = ["name"]

    with {:ok, _} <- validate_has_any_key(data, eve_id_keys),
         {:ok, validated} <- validate_required_fields(data, required_fields) do
      {:ok, validated}
    end
  end

  def validate_character_data(_), do: {:error, :not_a_map}

  @doc """
  Validates generic killmail data structure.

  ## Examples
      iex> killmail = %{"killmail_id" => 12345, "victim" => %{}}
      iex> validate_killmail_data(killmail)
      {:ok, killmail}
  """
  @spec validate_killmail_data(map()) :: {:ok, map()} | {:error, term()}
  def validate_killmail_data(data) when is_map(data) do
    required_keys = ["killmail_id", "victim"]

    with {:ok, _} <- validate_has_any_key(data, required_keys) do
      {:ok, data}
    end
  end

  def validate_killmail_data(_), do: {:error, :not_a_map}
end
