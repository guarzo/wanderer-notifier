defmodule WandererNotifier.Infrastructure.Http.Validation do
  require Logger

  @moduledoc """
  Centralized JSON validation logic for WandererNotifier.
  Provides consistent validation patterns for JSON data structures and HTTP responses.
  """

  alias WandererNotifier.Infrastructure.Http.Utils.JsonUtils
  alias WandererNotifier.Shared.Utils.TimeUtils
  alias WandererNotifier.Shared.Utils.ValidationUtils

  @type validation_result :: {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Validates and decodes JSON data.
  Returns {:ok, decoded} or {:error, reason}.
  """
  @spec decode_and_validate(binary() | map() | list()) :: validation_result()
  def decode_and_validate(data) when is_map(data), do: {:ok, data}
  def decode_and_validate(data) when is_list(data), do: {:ok, data}

  def decode_and_validate(data) when is_binary(data) do
    case JsonUtils.decode(data) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def decode_and_validate(_), do: {:error, :invalid_input}

  @doc """
  Validates that required fields are present in a map.
  Returns {:ok, map} if all fields are present, {:error, :missing_fields} otherwise.
  """
  @spec validate_required_fields(map(), [String.t() | atom()]) :: validation_result()
  def validate_required_fields(data, fields) when is_map(data) and is_list(fields) do
    case ValidationUtils.validate_required_fields(data, fields) do
      {:ok, validated_data} ->
        {:ok, validated_data}

      {:error, {:missing_fields, missing}} ->
        Logger.debug("Missing required fields", missing: missing, category: :api)
        {:error, {:missing_fields, missing}}

      {:error, {:empty_fields, empty}} ->
        Logger.debug("Empty required fields", empty: empty, category: :api)
        {:error, {:missing_fields, empty}}
    end
  end

  def validate_required_fields(_, _), do: {:error, :invalid_input}

  @doc """
  Validates field types in a map.
  Expects a spec map like %{"field_name" => :string, "other_field" => :integer}
  """
  @spec validate_field_types(map(), map()) :: validation_result()
  def validate_field_types(data, type_spec) when is_map(data) and is_map(type_spec) do
    errors =
      Enum.reduce(type_spec, [], fn {field, expected_type}, acc ->
        validate_field_type(data, field, expected_type, acc)
      end)

    case errors do
      [] -> {:ok, data}
      type_errors -> {:error, {:type_errors, Enum.reverse(type_errors)}}
    end
  end

  def validate_field_types(_, _), do: {:error, :invalid_input}

  defp validate_field_type(data, field, expected_type, acc) do
    case Map.get(data, field) do
      # Skip nil values, use validate_required_fields for presence
      nil ->
        acc

      value ->
        case valid_type?(value, expected_type) do
          true -> acc
          false -> [{field, expected_type, type_of(value)} | acc]
        end
    end
  end

  @doc """
  Safely extracts a nested value from a map.
  Returns {:ok, value} or {:error, :field_not_found}.
  """
  @spec extract_nested(map() | list(), [String.t() | atom() | integer()]) ::
          {:ok, any()} | {:error, :field_not_found}
  def extract_nested(data, path) when is_list(path) do
    case get_in(data, path) do
      nil -> {:error, :field_not_found}
      value -> {:ok, value}
    end
  end

  def extract_nested(_, _), do: {:error, :invalid_input}

  @doc """
  Validates and extracts a typed field from a map.
  Returns {:ok, value} if valid, {:error, reason} otherwise.
  """
  @spec extract_typed_field(map(), String.t() | atom(), atom()) ::
          {:ok, any()} | {:error, :field_not_found | :invalid_type}
  def extract_typed_field(data, field, expected_type) when is_map(data) do
    case Map.get(data, field) do
      nil ->
        {:error, :field_not_found}

      value ->
        if valid_type?(value, expected_type) do
          {:ok, value}
        else
          {:error, :invalid_type}
        end
    end
  end

  def extract_typed_field(_, _, _), do: {:error, :invalid_input}

  @doc """
  Validates a response structure matches expected format.
  """
  @spec validate_response_structure(map(), map()) :: validation_result()
  def validate_response_structure(response, expected_structure) do
    with {:ok, _} <- decode_and_validate(response),
         {:ok, _} <- validate_required_fields(response, Map.keys(expected_structure)),
         {:ok, _} <- validate_field_types(response, expected_structure) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Safely merges defaults into a map for missing fields.
  """
  @spec merge_defaults(map(), map()) :: map()
  def merge_defaults(data, defaults) when is_map(data) and is_map(defaults) do
    Map.merge(defaults, data)
  end

  def merge_defaults(data, _) when is_map(data), do: data
  def merge_defaults(_, defaults) when is_map(defaults), do: defaults
  def merge_defaults(_, _), do: %{}

  @doc """
  Validates an API response with status code and body.
  """
  @spec validate_api_response(%{status_code: integer(), body: any()}) ::
          {:ok, any()} | {:error, atom() | {atom(), integer()}}
  def validate_api_response(%{status_code: status, body: body})
      when status >= 200 and status < 300 do
    decode_and_validate(body)
  end

  def validate_api_response(%{status_code: 404}), do: {:error, :not_found}
  def validate_api_response(%{status_code: 429}), do: {:error, :rate_limited}

  def validate_api_response(%{status_code: status}) when status >= 400 and status < 500 do
    {:error, {:client_error, status}}
  end

  def validate_api_response(%{status_code: status}) when status >= 500 do
    {:error, {:server_error, status}}
  end

  def validate_api_response(_), do: {:error, :invalid_response}

  @doc """
  Creates a validated response with consistent structure.
  """
  @spec create_validated_response(map(), map()) :: map()
  def create_validated_response(data, defaults \\ %{}) do
    data
    |> merge_defaults(defaults)
    |> Map.put(:validated_at, TimeUtils.now())
  end

  # Private functions - now using ValidationUtils for consistency

  defp valid_type?(value, type), do: ValidationUtils.valid_type?(value, type)

  defp type_of(value), do: ValidationUtils.type_name(value) |> String.to_atom()
end
