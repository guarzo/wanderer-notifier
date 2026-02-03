defmodule WandererNotifier.Infrastructure.Http.Utils.JsonUtils do
  @moduledoc """
  JSON encoding and decoding utilities with proper error handling.
  """

  require Logger

  @type json_result :: {:ok, any()} | {:error, term()}
  @type encode_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Safely decodes a JSON string or returns the data if already decoded.

  ## Examples
      iex> JsonUtils.decode("{\"key\": \"value\"}")
      {:ok, %{"key" => "value"}}

      iex> JsonUtils.decode(%{"key" => "value"})
      {:ok, %{"key" => "value"}}

      iex> JsonUtils.decode("invalid json")
      {:error, :invalid_json}
  """
  @spec decode(String.t() | map() | list()) :: json_result()
  def decode(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  def decode(data) when is_map(data) or is_list(data) do
    {:ok, data}
  end

  def decode(_data) do
    {:error, :invalid_input_type}
  end

  @doc """
  Safely decodes a JSON string, returning nil on failure.

  ## Examples
      iex> JsonUtils.decode_safe("{\"key\": \"value\"}")
      %{"key" => "value"}

      iex> JsonUtils.decode_safe("invalid json")
      nil
  """
  @spec decode_safe(String.t() | map() | list()) :: any()
  def decode_safe(data) do
    case decode(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> nil
    end
  end

  @doc """
  Encodes data to JSON string with proper error handling.

  ## Examples
      iex> JsonUtils.encode(%{"key" => "value"})
      {:ok, "{\"key\":\"value\"}"}

      iex> JsonUtils.encode_safe(%{"key" => "value"})
      "{\"key\":\"value\"}"
  """
  @spec encode(any()) :: encode_result()
  def encode(data) do
    case Jason.encode(data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Encodes data to JSON string, raising on failure.
  Use only when you're certain the data is encodable.
  """
  @spec encode!(any()) :: String.t()
  def encode!(data) do
    Jason.encode!(data)
  end

  @doc """
  Safely encodes data to JSON string, returning nil on failure.
  """
  @spec encode_safe(any()) :: String.t() | nil
  def encode_safe(data) do
    case encode(data) do
      {:ok, json} -> json
      {:error, _} -> nil
    end
  end

  @doc """
  Encodes data to iodata for efficient streaming/sending.
  """
  @spec encode_to_iodata!(any()) :: iodata()
  def encode_to_iodata!(data) do
    Jason.encode_to_iodata!(data)
  end

  @doc """
  Decodes JSON data from HTTP response body with detailed error logging.
  Handles both binary and already-decoded responses.
  """
  @spec decode_http_response(String.t() | map() | list(), String.t()) :: json_result()
  def decode_http_response(body, context \\ "HTTP response") do
    case decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        Logger.debug(
          "Failed to decode JSON in #{context}: #{inspect(reason)}, body: #{inspect(body)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Safely tries to parse error information from a response body.
  Returns a map with error details or the original body if parsing fails.
  """
  @spec parse_error_response(String.t() | map()) :: map()
  def parse_error_response(body) when is_binary(body) do
    case decode_safe(body) do
      %{"error" => _error} = data -> data
      %{"message" => _message} = data -> data
      nil -> %{"error" => "Failed to parse error response", "raw_body" => body}
      other -> other
    end
  end

  def parse_error_response(body) when is_map(body), do: body
  def parse_error_response(body), do: %{"error" => "Unknown error format", "raw_body" => body}

  @doc """
  Validates that the given data is valid JSON encodable structure.
  """
  @spec valid_json?(any()) :: boolean()
  def valid_json?(data) do
    case encode(data) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Pretty-prints JSON with indentation for debugging purposes.
  """
  @spec pretty_encode(any()) :: encode_result()
  def pretty_encode(data) do
    Jason.encode(data, pretty: true)
  end

  @doc """
  Pretty-prints JSON, returning the original data as string if encoding fails.
  """
  @spec pretty_encode_safe(any()) :: String.t()
  def pretty_encode_safe(data) do
    case pretty_encode(data) do
      {:ok, json} -> json
      {:error, _} -> inspect(data)
    end
  end
end
