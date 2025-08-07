defmodule WandererNotifier.Shared.Utils.StringUtils do
  @moduledoc """
  Shared string utilities for the application.

  Contains common string manipulation and validation functions
  used throughout the codebase.
  """

  @doc """
  Checks if a value is nil or an empty string.

  ## Examples

      iex> StringUtils.nil_or_empty?(nil)
      true
      
      iex> StringUtils.nil_or_empty?("")
      true
      
      iex> StringUtils.nil_or_empty?("   ")
      true
      
      iex> StringUtils.nil_or_empty?("hello")
      false
  """
  @spec nil_or_empty?(any()) :: boolean()
  def nil_or_empty?(nil), do: true
  def nil_or_empty?(""), do: true
  def nil_or_empty?(value) when is_binary(value), do: String.trim(value) == ""
  def nil_or_empty?(_), do: false

  @doc """
  Checks if a value is present (not nil or empty).

  This is the opposite of `nil_or_empty?/1` and provides better readability
  when checking for presence rather than absence.

  ## Examples

      iex> StringUtils.present?(nil)
      false
      
      iex> StringUtils.present?("")
      false
      
      iex> StringUtils.present?("hello")
      true
  """
  @spec present?(any()) :: boolean()
  def present?(value), do: not nil_or_empty?(value)
end
