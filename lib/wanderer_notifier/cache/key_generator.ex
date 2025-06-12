defmodule WandererNotifier.Cache.KeyGenerator do
  @moduledoc """
  Consolidated key generation utilities for cache operations.
  Provides macros and functions for generating standardized cache keys.

  Key Format: `prefix:entity_type:id` or `prefix:name`
  Examples:
    - `map:system:12345`
    - `tracked:character:98765`
    - `recent:kills`
  """

  @separator ":"

  @doc """
  Core function for combining key parts into a standardized cache key.
  This is the central implementation used by all key generation functions.

  ## Parameters
  - fixed_parts: List of static key components (e.g., prefixes, entity types)
  - dynamic_parts: List of dynamic components (e.g., IDs, names)
  - extra: Optional additional component

  ## Examples
      iex> combine(["map", "system"], [12345], nil)
      "map:system:12345"

      iex> combine(["zkill"], ["recent_kills"], "cached")
      "zkill:recent_kills:cached"
  """
  @spec combine(list(term()), list(term()), term() | nil) :: String.t()
  def combine(fixed_parts, dynamic_parts, extra)
      when is_list(fixed_parts) and is_list(dynamic_parts) do
    # Convert all parts to string, treating nil as empty string for id positions
    # but filtering out nil extra values
    all_parts = fixed_parts ++ dynamic_parts ++ if extra, do: [extra], else: []

    all_parts
    |> Enum.map(fn
      # Convert nil to empty string to preserve key structure
      nil -> ""
      val -> to_string(val)
    end)
    |> join_parts()
  end

  @doc """
  Joins key parts with the standard separator.
  """
  @spec join_parts(list(String.t())) :: String.t()
  def join_parts(parts) when is_list(parts) do
    Enum.join(parts, @separator)
  end

  @doc """
  Validates if a key follows the expected format.
  Returns true if the key contains at least one separator and two parts.
  """
  @spec valid_key?(String.t()) :: boolean()
  def valid_key?(key) when is_binary(key) do
    String.contains?(key, @separator) and length(String.split(key, @separator)) >= 2
  end

  def valid_key?(_), do: false

  @doc """
  Parses a cache key into its component parts.
  Returns structured information about the key or {:error, :invalid_key}.
  """
  @spec parse_key(String.t()) :: map() | {:error, :invalid_key}
  def parse_key(key) when is_binary(key) do
    if valid_key?(key) do
      parts = String.split(key, @separator)

      case parts do
        [prefix, entity, id | rest] ->
          %{prefix: prefix, entity_type: entity, id: id, parts: parts, extra: rest}

        [prefix, name] ->
          %{prefix: prefix, name: name, parts: parts}

        _ ->
          %{parts: parts}
      end
    else
      {:error, :invalid_key}
    end
  end

  def parse_key(_), do: {:error, :invalid_key}

  @doc """
  Extracts wildcard segments from a key given a pattern.
  Useful for pattern matching cache keys.
  """
  @spec extract_pattern(String.t(), String.t()) :: [String.t()]
  def extract_pattern(key, pattern) when is_binary(key) and is_binary(pattern) do
    key_parts = String.split(key, @separator)
    pattern_parts = String.split(pattern, @separator)

    if length(key_parts) == length(pattern_parts) do
      do_extract(key_parts, pattern_parts, [])
    else
      []
    end
  end

  def extract_pattern(_, _), do: []

  defp do_extract([], [], acc), do: Enum.reverse(acc)
  defp do_extract([k | kr], ["*" | pr], acc), do: do_extract(kr, pr, [k | acc])
  defp do_extract([k | kr], [p | pr], acc) when k == p, do: do_extract(kr, pr, acc)
  defp do_extract(_, _, _), do: []

  @doc """
  Macro for generating standard cache key functions.
  Creates functions that follow the pattern: prefix:entity:id
  """
  defmacro defkey(name, prefix, entity, _opts \\ []) do
    quote do
      @doc "Key for #{unquote(entity)}: #{unquote(prefix)}:#{unquote(entity)}:id"
      @spec unquote(name)(integer() | String.t(), String.t() | nil) :: String.t()
      def unquote(name)(id, extra \\ nil) do
        WandererNotifier.Cache.KeyGenerator.combine(
          [unquote(prefix), unquote(entity)],
          [id],
          extra
        )
      end
    end
  end

  @doc """
  Macro for generating simple prefix-based key functions.
  Creates functions that follow the pattern: prefix:name
  """
  defmacro defkey_simple(name, prefix, suffix \\ nil) do
    parts_expr =
      if suffix,
        do: quote(do: [unquote(prefix), unquote(suffix)]),
        else: quote(do: [unquote(prefix)])

    quote do
      @doc "Key for #{unquote(name)}: #{unquote(prefix)}#{if unquote(suffix), do: ":#{unquote(suffix)}", else: ""}"
      @spec unquote(name)() :: String.t()
      def unquote(name)() do
        WandererNotifier.Cache.KeyGenerator.combine(unquote(parts_expr), [], nil)
      end
    end
  end

  @doc """
  Macro for generating complex key functions with multiple dynamic parts.
  """
  defmacro defkey_complex(name, prefix, _parts_count) do
    quote do
      @doc "Complex key for #{unquote(name)}: #{unquote(prefix)}:..."
      @spec unquote(name)(list(term()), String.t() | nil) :: String.t()
      def unquote(name)(dynamic_parts, extra \\ nil) when is_list(dynamic_parts) do
        WandererNotifier.Cache.KeyGenerator.combine([unquote(prefix)], dynamic_parts, extra)
      end
    end
  end
end
