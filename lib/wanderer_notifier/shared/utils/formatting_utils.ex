defmodule WandererNotifier.Shared.Utils.FormattingUtils do
  @moduledoc """
  Centralized formatting utilities for consistent display across the application.

  This module consolidates all formatting logic, particularly ISK (InterStellar Kredits)
  currency formatting, to ensure consistent presentation throughout the codebase.
  """

  @doc """
  Formats ISK values with configurable options.

  ## Options
    * `:precision` - Number of decimal places (default: 1)
    * `:suffix` - Whether to include "ISK" suffix (default: true)
    * `:format` - Display format `:short` or `:long` (default: `:short`)

  ## Examples
      iex> format_isk(1_500_000_000)
      "1.5B ISK"
      
      iex> format_isk(1_500_000_000, suffix: false)
      "1.5B"
      
      iex> format_isk(1_500_000_000, precision: 2)
      "1.50B ISK"
      
      iex> format_isk(1_500_000_000, format: :long)
      "1,500,000,000 ISK"
  """
  @spec format_isk(number(), keyword()) :: String.t()
  def format_isk(value, opts \\ []) when is_number(value) do
    precision = Keyword.get(opts, :precision, 1)
    suffix = Keyword.get(opts, :suffix, true)
    format = Keyword.get(opts, :format, :short)

    formatted =
      case format do
        :short -> format_short(value, precision)
        :long -> format_with_commas(value)
        _ -> format_short(value, precision)
      end

    if suffix do
      "#{formatted} ISK"
    else
      formatted
    end
  end

  @doc """
  Formats ISK in short format with suffix (most common use case).

  ## Examples
      iex> format_isk_short(2_500_000_000)
      "2.5B ISK"
  """
  @spec format_isk_short(number()) :: String.t()
  def format_isk_short(value), do: format_isk(value)

  @doc """
  Formats ISK in short format without suffix.

  ## Examples
      iex> format_isk_no_suffix(2_500_000_000)
      "2.5B"
  """
  @spec format_isk_no_suffix(number()) :: String.t()
  def format_isk_no_suffix(value), do: format_isk(value, suffix: false)

  @doc """
  Formats ISK with full numeric display and comma separators.

  ## Examples
      iex> format_isk_full(2_500_000_000)
      "2,500,000,000 ISK"
  """
  @spec format_isk_full(number()) :: String.t()
  def format_isk_full(value), do: format_isk(value, format: :long)

  @doc """
  Formats a number with thousand separators.

  ## Examples
      iex> format_number(1234567)
      "1,234,567"
      
      iex> format_number(1234567.89)
      "1,234,567.89"
  """
  @spec format_number(number()) :: String.t()
  def format_number(value) when is_number(value) do
    format_with_commas(value)
  end

  @doc """
  Formats a percentage value.

  ## Examples
      iex> format_percentage(0.756)
      "75.6%"
      
      iex> format_percentage(0.756, precision: 0)
      "76%"
  """
  @spec format_percentage(number(), keyword()) :: String.t()
  def format_percentage(value, opts \\ []) when is_number(value) do
    precision = Keyword.get(opts, :precision, 1)
    # Ensure it's a float
    percentage = value * 100.0

    :erlang.float_to_binary(percentage, decimals: precision) <> "%"
  end

  # Private functions

  defp format_short(value, precision) when value >= 1_000_000_000 do
    :erlang.float_to_binary(value / 1_000_000_000, decimals: precision) <> "B"
  end

  defp format_short(value, precision) when value >= 1_000_000 do
    :erlang.float_to_binary(value / 1_000_000, decimals: precision) <> "M"
  end

  defp format_short(value, precision) when value >= 1_000 do
    :erlang.float_to_binary(value / 1_000, decimals: precision) <> "K"
  end

  defp format_short(value, _precision) do
    value
    |> round()
    |> Integer.to_string()
  end

  defp format_with_commas(value) when is_float(value) do
    parts =
      value
      |> Float.to_string()
      |> String.split(".", parts: 2)

    case parts do
      [integer_part] -> add_commas(integer_part)
      [integer_part, decimal_part] -> "#{add_commas(integer_part)}.#{decimal_part}"
    end
  end

  defp format_with_commas(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> add_commas()
  end

  defp add_commas(string) when is_binary(string) do
    string
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
