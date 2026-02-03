defmodule WandererNotifier.Shared.Validation do
  @moduledoc """
  Unified validation module for all validation patterns across the application.

  ## Design Principles

  - **Consistent Error Format**: All validation functions return standardized error tuples
  - **Composable Functions**: Small, focused functions that can be combined
  - **Domain-Agnostic Core**: Generic validation with domain-specific extensions
  - **Performance Optimized**: Minimal overhead with fast-fail strategies
  - **Type Safety**: Clear specs and comprehensive error handling

  ## Usage Categories

  ### Basic Type & Structure Validation
  ```elixir
  Validation.validate_type(value, :string)
  Validation.validate_required_fields(data, ["name", "id"])
  Validation.validate_map_structure(data, %{name: :string, id: :integer})
  ```

  ### HTTP & API Validation
  ```elixir
  Validation.validate_http_response(%{status_code: 200, body: data})
  Validation.validate_json_structure(json_string, required_fields)
  ```

  ### Domain-Specific Validation
  ```elixir
  Validation.validate_killmail_data(killmail)
  Validation.validate_character_data(character)
  Validation.validate_system_data(system)
  ```

  ### Configuration & License Validation
  ```elixir
  Validation.validate_license_response(response)
  Validation.validate_config_present([:license_key, :api_token])
  ```
  """

  require Logger

  # ══════════════════════════════════════════════════════════════════════════════
  # Types and Constants
  # ══════════════════════════════════════════════════════════════════════════════

  @type validation_result :: {:ok, any()} | {:error, validation_error()}
  @type validation_error :: atom() | {atom(), any()}
  @type field_list :: [String.t() | atom()]
  @type type_spec :: %{atom() => atom()}

  # Standard HTTP status codes for API validation
  @success_status_range 200..299
  @client_error_range 400..499
  @server_error_range 500..599

  # ══════════════════════════════════════════════════════════════════════════════
  # Core Type Validation (from ValidationUtils)
  # ══════════════════════════════════════════════════════════════════════════════

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
  """
  @spec validate_type(any(), atom()) :: boolean()
  def validate_type(value, :string), do: is_binary(value)
  def validate_type(value, :integer), do: is_integer(value)
  def validate_type(value, :float), do: is_float(value)
  def validate_type(value, :number), do: is_number(value)
  def validate_type(value, :boolean), do: is_boolean(value)
  def validate_type(value, :map), do: is_map(value)
  def validate_type(value, :list), do: is_list(value)
  def validate_type(value, :atom), do: is_atom(value)
  def validate_type(_, :any), do: true
  def validate_type(_, _), do: false

  @doc """
  Validates that required fields are present and non-empty in a map.

  Returns {:ok, data} if all fields are present and non-empty.
  Returns {:error, reason} with detailed information about missing/empty fields.
  """
  @spec validate_required_fields(map(), field_list()) :: validation_result()
  def validate_required_fields(data, fields) when is_map(data) and is_list(fields) do
    string_fields = Enum.map(fields, &to_string/1)
    {missing, empty} = categorize_field_errors(data, string_fields)
    build_field_validation_result(data, missing, empty)
  end

  def validate_required_fields(_, _), do: {:error, :invalid_input}

  @doc """
  Validates a map against a schema defining field types.

  ## Example
      iex> schema = %{name: :string, id: :integer, active: :boolean}
      iex> data = %{"name" => "test", "id" => 1, "active" => true}
      iex> validate_map_structure(data, schema)
      {:ok, %{"name" => "test", "id" => 1, "active" => true}}
  """
  @spec validate_map_structure(map(), type_spec()) :: validation_result()
  def validate_map_structure(data, schema) when is_map(data) and is_map(schema) do
    type_errors = collect_type_errors(data, schema)
    format_type_validation_result(data, type_errors)
  end

  def validate_map_structure(_, _), do: {:error, :invalid_input}

  @doc """
  Validates a complete data structure with both required fields and type checking.
  """
  @spec validate_data_structure(map(), type_spec(), field_list()) :: validation_result()
  def validate_data_structure(data, schema, required_fields) do
    with {:ok, _} <- validate_required_fields(data, required_fields),
         {:ok, validated} <- validate_map_structure(data, schema) do
      {:ok, validated}
    end
  end

  @doc """
  Validates that a map contains at least one of the specified keys.
  """
  @spec validate_has_any_key(map(), field_list()) :: validation_result()
  def validate_has_any_key(data, keys) when is_map(data) and is_list(keys) do
    string_keys = Enum.map(keys, &to_string/1)
    has_any_key = Enum.any?(string_keys, &Map.has_key?(data, &1))

    if has_any_key do
      {:ok, data}
    else
      {:error, {:missing_any_key, string_keys}}
    end
  end

  def validate_has_any_key(_, _), do: {:error, :invalid_input}

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
  @spec validate_optional_field(any(), atom()) :: validation_result()
  def validate_optional_field(nil, _type), do: {:ok, nil}

  def validate_optional_field(value, type) do
    if validate_type(value, type) do
      {:ok, value}
    else
      {:error, :invalid_type}
    end
  end

  @doc """
  Validates that all items in a list pass a validation function.
  """
  @spec validate_list(list(), (any() -> boolean())) :: validation_result()
  def validate_list(items, validator_fn) when is_list(items) and is_function(validator_fn, 1) do
    invalid_indices = find_invalid_list_items(items, validator_fn)

    case invalid_indices do
      [] -> {:ok, items}
      indices -> {:error, {:invalid_items, indices}}
    end
  end

  def validate_list(_, _), do: {:error, :invalid_input}

  @doc """
  Validates that a value is a non-empty map.
  """
  @spec valid_non_empty_map?(any()) :: boolean()
  def valid_non_empty_map?(value) do
    is_map(value) and map_size(value) > 0
  end

  @doc """
  Validates that a string field is either nil or a non-empty string.
  Useful for optional string fields that should not be empty if provided.
  """
  @spec valid_optional_string_field?(any()) :: boolean()
  def valid_optional_string_field?(nil), do: true
  def valid_optional_string_field?(value) when is_binary(value), do: value != ""
  def valid_optional_string_field?(_), do: false

  # ══════════════════════════════════════════════════════════════════════════════
  # HTTP & JSON Validation (consolidated from Infrastructure.Http.Validation)
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Validates and decodes JSON data with consistent error handling.
  """
  @spec validate_json(binary() | map() | list()) :: validation_result()
  def validate_json(data) when is_map(data), do: {:ok, data}
  def validate_json(data) when is_list(data), do: {:ok, data}

  def validate_json(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def validate_json(_), do: {:error, :invalid_input}

  @doc """
  Validates an HTTP API response with status code and body.
  """
  @spec validate_http_response(%{status_code: integer(), body: any()}) :: validation_result()
  def validate_http_response(%{status_code: status, body: body})
      when status in @success_status_range do
    validate_json(body)
  end

  def validate_http_response(%{status_code: 404}), do: {:error, :not_found}
  def validate_http_response(%{status_code: 429}), do: {:error, :rate_limited}

  def validate_http_response(%{status_code: status}) when status in @client_error_range do
    {:error, {:client_error, status}}
  end

  def validate_http_response(%{status_code: status}) when status in @server_error_range do
    {:error, {:server_error, status}}
  end

  def validate_http_response(_), do: {:error, :invalid_response}

  @doc """
  Safely extracts a nested value from a map with path traversal.
  """
  @spec extract_nested_field(map() | list(), [String.t() | atom() | integer()]) ::
          validation_result()
  def extract_nested_field(data, path) when is_list(path) do
    case get_in(data, path) do
      nil -> {:error, :field_not_found}
      value -> {:ok, value}
    end
  end

  def extract_nested_field(_, _), do: {:error, :invalid_input}

  @doc """
  Validates and extracts a typed field from a map.
  """
  @spec extract_typed_field(map(), String.t() | atom(), atom()) :: validation_result()
  def extract_typed_field(data, field, expected_type) when is_map(data) do
    case Map.get(data, field) do
      nil ->
        {:error, :field_not_found}

      value ->
        if validate_type(value, expected_type) do
          {:ok, value}
        else
          {:error, :invalid_type}
        end
    end
  end

  def extract_typed_field(_, _, _), do: {:error, :invalid_input}

  # ══════════════════════════════════════════════════════════════════════════════
  # Configuration & License Validation (from License.Validation)
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Normalizes license API response to consistent format.
  Handles both 'license_valid' and 'valid' response formats.
  """
  @spec validate_license_response(map()) :: validation_result()
  def validate_license_response(%{"license_valid" => license_valid} = response) do
    normalized = %{
      valid: license_valid,
      bot_assigned: response["bot_associated"] || response["bot_assigned"] || false,
      message: response["message"],
      raw_response: response
    }

    {:ok, normalized}
  end

  def validate_license_response(%{"valid" => valid} = response) do
    normalized = %{
      valid: valid,
      bot_assigned: response["bot_associated"] || response["bot_assigned"] || false,
      message: response["message"],
      raw_response: response
    }

    {:ok, normalized}
  end

  def validate_license_response(_), do: {:error, :invalid_response}

  @doc """
  Validates that required configuration values are present and non-empty.
  """
  @spec validate_config_present([atom()]) :: validation_result()
  def validate_config_present(config_keys) when is_list(config_keys) do
    missing = Enum.filter(config_keys, &config_value_missing?/1)

    case missing do
      [] -> {:ok, :all_present}
      missing_keys -> {:error, {:missing_config, missing_keys}}
    end
  end

  def validate_config_present(_), do: {:error, :invalid_input}

  # ══════════════════════════════════════════════════════════════════════════════
  # Domain-Specific Validation (consolidating domain patterns)
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Validates killmail data structure with required fields.
  """
  @spec validate_killmail_data(map()) :: validation_result()
  def validate_killmail_data(data) when is_map(data) do
    required_keys = ["killmail_id", "victim"]
    validate_has_any_key(data, required_keys)
  end

  def validate_killmail_data(_), do: {:error, :not_a_map}

  @doc """
  Validates character data structure.
  Supports both "eve_id" and "character_eve_id" formats.
  """
  @spec validate_character_data(map()) :: validation_result()
  def validate_character_data(data) when is_map(data) do
    eve_id_keys = ["eve_id", "character_eve_id"]
    required_fields = ["name"]

    with {:ok, _} <- validate_has_any_key(data, eve_id_keys),
         {:ok, validated} <- validate_required_fields(data, required_fields) do
      {:ok, validated}
    end
  end

  def validate_character_data(_), do: {:error, :not_a_map}

  @doc """
  Validates system data structure with comprehensive field validation.
  """
  @spec validate_system_data(map()) :: validation_result()
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
         {:ok, validated} <- validate_map_structure(data, schema),
         {:ok, _} <- validate_optional_string_fields(data) do
      {:ok, validated}
    end
  end

  def validate_system_data(_), do: {:error, :not_a_map}

  @doc """
  Validates SSE event structure with required fields and payload.
  """
  @spec validate_event_data(map()) :: validation_result()
  def validate_event_data(event) when is_map(event) do
    required_fields = ["id", "type", "map_id", "timestamp", "payload"]

    with {:ok, _} <- validate_required_fields(event, required_fields) do
      validate_event_payload(event)
    end
  end

  def validate_event_data(_), do: {:error, :invalid_event_structure}

  # ══════════════════════════════════════════════════════════════════════════════
  # Error Formatting & Utilities
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats validation errors into human-readable messages.
  """
  @spec format_validation_error(validation_error()) :: String.t()
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

  def format_validation_error({:missing_config, keys}) do
    "Missing configuration: #{Enum.join(Enum.map(keys, &to_string/1), ", ")}"
  end

  def format_validation_error(:invalid_json), do: "Invalid JSON format"
  def format_validation_error(:not_found), do: "Resource not found"
  def format_validation_error(:rate_limited), do: "Rate limit exceeded"
  def format_validation_error(:invalid_type), do: "Invalid type for field"
  def format_validation_error(:field_not_found), do: "Field not found"
  def format_validation_error(:invalid_response), do: "Invalid response format"
  def format_validation_error(:invalid_input), do: "Invalid input provided"
  def format_validation_error(:not_a_map), do: "Expected map data structure"
  def format_validation_error(:invalid_event_structure), do: "Invalid event structure"
  def format_validation_error(:invalid_payload), do: "Invalid or empty payload"

  def format_validation_error({:client_error, status}), do: "Client error: #{status}"
  def format_validation_error({:server_error, status}), do: "Server error: #{status}"

  def format_validation_error(error), do: "Validation error: #{inspect(error)}"

  @doc """
  Returns a human-readable name for a value's type.
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

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Implementation Functions
  # ══════════════════════════════════════════════════════════════════════════════

  # Field validation helpers
  defp categorize_field_errors(data, fields) do
    Enum.reduce(fields, {[], []}, fn field, {missing_acc, empty_acc} ->
      case Map.get(data, field) do
        nil -> {[field | missing_acc], empty_acc}
        "" -> {missing_acc, [field | empty_acc]}
        _value -> {missing_acc, empty_acc}
      end
    end)
  end

  defp build_field_validation_result(data, [], []), do: {:ok, data}

  defp build_field_validation_result(_data, missing, []) when missing != [],
    do: {:error, {:missing_fields, Enum.reverse(missing)}}

  defp build_field_validation_result(_data, _missing, empty) when empty != [],
    do: {:error, {:empty_fields, Enum.reverse(empty)}}

  # Type validation helpers
  defp collect_type_errors(data, schema) do
    Enum.reduce(schema, [], fn {field, expected_type}, acc ->
      validate_field_type(data, field, expected_type, acc)
    end)
  end

  defp validate_field_type(data, field, expected_type, acc) do
    field_str = to_string(field)

    case Map.get(data, field_str) do
      # Missing fields handled by validate_required_fields
      nil ->
        acc

      value ->
        if validate_type(value, expected_type) do
          acc
        else
          [{field_str, expected_type, value} | acc]
        end
    end
  end

  defp format_type_validation_result(data, []), do: {:ok, data}

  defp format_type_validation_result(_data, errors),
    do: {:error, {:type_errors, Enum.reverse(errors)}}

  # List validation helpers
  defp find_invalid_list_items(items, validator_fn) do
    items
    |> Enum.with_index()
    |> Enum.reduce([], fn {item, index}, acc ->
      if validator_fn.(item), do: acc, else: [index | acc]
    end)
    |> Enum.reverse()
  end

  # Configuration helpers
  defp config_value_missing?(key) do
    case Application.get_env(:wanderer_notifier, key) do
      nil -> true
      "" -> true
      _value -> false
    end
  end

  # Domain-specific helpers
  defp validate_optional_string_fields(data) do
    optional_fields = ["custom_name", "description", "original_name", "temporary_name", "tag"]

    invalid_fields =
      Enum.filter(optional_fields, fn field ->
        case Map.get(data, field) do
          nil -> false
          value when is_binary(value) -> value == ""
          _non_string -> true
        end
      end)

    case invalid_fields do
      [] -> {:ok, data}
      invalid -> {:error, {:invalid_optional_fields, invalid}}
    end
  end

  defp validate_event_payload(event) do
    payload = Map.get(event, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      {:ok, event}
    else
      {:error, :invalid_payload}
    end
  end
end
