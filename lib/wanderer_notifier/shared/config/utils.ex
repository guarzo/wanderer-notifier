defmodule WandererNotifier.Shared.Config.Utils do
  @moduledoc """
  Utility functions for configuration parsing and validation.
  Contains common helpers for environment variable parsing, URL handling,
  boolean validation, and other configuration-related tasks.
  """

  require Logger

  @default_port 4000
  @min_port 1
  @max_port 65_535

  @doc """
  Parses an integer from a string value with error handling.
  Returns the default value if parsing fails.

  ## Examples
      iex> parse_int("123", 0)
      123

      iex> parse_int("invalid", 42)
      42

      iex> parse_int(nil, 100)
      100
  """
  @spec parse_int(String.t() | nil, integer() | nil) :: integer() | nil
  def parse_int(nil, default), do: default

  def parse_int(str, default) when is_binary(str) do
    trimmed = String.trim(str)

    case Integer.parse(trimmed) do
      {i, _} ->
        i

      :error ->
        Logger.warning(
          "Unable to parse integer from value #{inspect(str)} – falling back to #{default}"
        )

        default
    end
  end

  def parse_int(value, _default) when is_integer(value), do: value
  def parse_int(_, default), do: default

  @doc """
  Parses a port number with validation and type conversion.
  Handles both integer and string inputs.

  ## Examples
      iex> parse_port(8080)
      8080

      iex> parse_port("8080")
      8080

      iex> parse_port("invalid")
      4000
  """
  @spec parse_port(integer() | String.t() | any()) :: integer()
  def parse_port(port) when is_integer(port) and port in @min_port..@max_port, do: port
  def parse_port(port) when is_integer(port), do: fallback_port(port)

  def parse_port(str) when is_binary(str) do
    case String.trim(str) |> Integer.parse() do
      {int, ""} -> parse_port(int)
      _ -> fallback_port(str)
    end
  end

  def parse_port(_), do: @default_port

  defp fallback_port(port) do
    Logger.warning(fn ->
      "Invalid port #{inspect(port)}. Using default #{@default_port}."
    end)

    @default_port
  end

  @doc """
  Checks if a string value is nil or empty.

  ## Examples
      iex> nil_or_empty?(nil)
      true

      iex> nil_or_empty?("")
      true

      iex> nil_or_empty?("valid")
      false
  """
  @spec nil_or_empty?(String.t() | nil) :: boolean()
  def nil_or_empty?(str), do: is_nil(str) or str == ""

  @doc """
  Extracts a map name from a URL's query parameters.
  Returns empty string if no name parameter is found.

  ## Examples
      iex> parse_map_name_from_url("http://example.com?name=test")
      "test"

      iex> parse_map_name_from_url("http://example.com")
      ""
  """
  @spec parse_map_name_from_url(String.t() | nil) :: String.t()
  def parse_map_name_from_url(url) when is_nil(url), do: ""

  def parse_map_name_from_url(url) when is_binary(url) do
    if nil_or_empty?(url) do
      ""
    else
      uri = URI.parse(url)

      case uri.query do
        nil ->
          ""

        query_string ->
          URI.decode_query(query_string)
          |> Map.get("name", "")
      end
    end
  end

  @doc """
  Extracts a slug from the last segment of a URL path.
  Returns empty string if no valid path is found.

  ## Examples
      iex> extract_slug_from_url("http://example.com/maps/my-map")
      "my-map"

      iex> extract_slug_from_url("http://example.com")
      ""
  """
  @spec extract_slug_from_url(String.t() | nil) :: String.t()
  def extract_slug_from_url(url) when is_nil(url), do: ""

  def extract_slug_from_url(url) when is_binary(url) do
    if nil_or_empty?(url) do
      ""
    else
      uri = URI.parse(url)
      extract_path_slug(uri, url)
    end
  end

  @doc """
  Builds a base URL from a full URL, removing query parameters and path.
  Handles default ports appropriately.

  ## Examples
      iex> build_base_url("http://example.com:8080/path?query=value")
      "http://example.com:8080"

      iex> build_base_url("https://example.com/path")
      "https://example.com"
  """
  @spec build_base_url(String.t() | nil) :: String.t()
  def build_base_url(url) when is_nil(url) do
    log_invalid_url("Missing URL")
    ""
  end

  def build_base_url(url) when is_binary(url) do
    if nil_or_empty?(url) do
      log_invalid_url("Missing URL")
      ""
    else
      uri = URI.parse(url)

      if has_valid_scheme_and_host?(uri) do
        build_url_from_components(uri)
      else
        log_invalid_url("Invalid URL format: #{url}")
        ""
      end
    end
  end

  @doc """
  Parses a comma-separated string into a trimmed list.
  Useful for parsing environment variables with multiple values.

  ## Examples
      iex> parse_comma_list("a,b,c")
      ["a", "b", "c"]

      iex> parse_comma_list("a, b , c ")
      ["a", "b", "c"]

      iex> parse_comma_list("")
      []
  """
  @spec parse_comma_list(String.t() | nil) :: [String.t()]
  def parse_comma_list(nil), do: []
  def parse_comma_list(""), do: []

  def parse_comma_list(str) when is_binary(str) do
    str |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  @doc """
  Parses a boolean value from a string with fallback to default.
  Handles common true/false string representations.

  ## Examples
      iex> parse_bool("true", false)
      true

      iex> parse_bool("false", true)
      false

      iex> parse_bool("invalid", false)
      false

      iex> parse_bool(nil, true)
      true
  """
  @spec parse_bool(String.t() | nil, boolean()) :: boolean()
  def parse_bool(nil, default), do: default
  def parse_bool("", default), do: default

  def parse_bool(str, default) when is_binary(str) do
    normalized_value = str |> String.trim() |> String.downcase()

    cond do
      truthy_value?(normalized_value) -> true
      falsy_value?(normalized_value) -> false
      true -> log_invalid_bool_and_return_default(str, default)
    end
  end

  def parse_bool(value, _default) when is_boolean(value), do: value
  def parse_bool(_, default), do: default

  defp truthy_value?(value), do: value in ["true", "1", "yes", "on"]
  defp falsy_value?(value), do: value in ["false", "0", "no", "off"]

  defp log_invalid_bool_and_return_default(str, default) do
    Logger.warning(
      "Unable to parse boolean from value #{inspect(str)} – falling back to #{default}"
    )

    default
  end

  @doc """
  Normalizes feature configuration to a keyword list.
  Handles both map and keyword list inputs.

  ## Examples
      iex> normalize_features(%{feature1: true, feature2: false})
      [feature1: true, feature2: false]

      iex> normalize_features([feature1: true, feature2: false])
      [feature1: true, feature2: false]

      iex> normalize_features("invalid")
      []
  """
  @spec normalize_features(map() | keyword() | any()) :: keyword()
  def normalize_features(features) when is_map(features) do
    Enum.to_list(features)
  end

  def normalize_features(features) when is_list(features) do
    if Keyword.keyword?(features), do: features, else: []
  end

  def normalize_features(_), do: []

  # Private helper functions

  defp extract_path_slug(uri, original_url) do
    if uri.path != nil and uri.path != "" do
      uri.path |> String.trim("/") |> String.split("/") |> List.last()
    else
      Logger.warning("No path in URL: #{original_url}")
      ""
    end
  end

  defp log_invalid_url(message) do
    Logger.warning(message)
  end

  defp has_valid_scheme_and_host?(uri) do
    uri.scheme != nil and uri.host != nil
  end

  defp build_url_from_components(uri) do
    port_part = format_port(uri.scheme, uri.port)
    "#{uri.scheme}://#{uri.host}#{port_part}"
  end

  defp format_port("http", 80), do: ""
  defp format_port("https", 443), do: ""
  defp format_port(_scheme, nil), do: ""
  defp format_port(_scheme, port), do: ":#{port}"

  @doc """
  Parses system ID from various input types.

  ## Examples
      iex> parse_system_id("30000142")
      30000142
      
      iex> parse_system_id(30000142)
      30000142
      
      iex> parse_system_id("invalid")
      nil
  """
  @spec parse_system_id(binary() | integer() | any()) :: integer() | nil
  def parse_system_id(id) when is_binary(id) do
    parse_int(id, nil)
  end

  def parse_system_id(id) when is_integer(id), do: id
  def parse_system_id(_), do: nil
end
