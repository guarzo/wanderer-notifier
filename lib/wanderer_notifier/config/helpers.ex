defmodule WandererNotifier.Config.Helpers do
  @moduledoc """
  Helper functions for parsing configuration values.
  """

  @doc """
  Safely parses an integer from a string value.
  Returns the default value if parsing fails.
  """
  def parse_int(value, default) when is_binary(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {int, _} -> int
      :error -> default
    end
  end

  def parse_int(nil, default), do: default
  def parse_int(value, _default) when is_integer(value), do: value
  def parse_int(_, default), do: default

  @doc """
  Parses a boolean value from a string.
  Only accepts "true" or "false" (case-insensitive).
  Returns the default value for any other input.
  """
  def parse_bool(value, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  def parse_bool(nil, default), do: default
  def parse_bool(value, _) when is_boolean(value), do: value
  def parse_bool(_, default), do: default
end
