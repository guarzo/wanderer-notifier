defmodule WandererNotifier.Utilities.NumberHuman do
  @moduledoc """
  Utility module for formatting numbers in a human-readable way.
  """

  @doc """
  Converts a number to a human-readable string with appropriate suffix.

  ## Examples
      iex> number_to_human(1234)
      "1.2K"

      iex> number_to_human(1234567)
      "1.2M"

      iex> number_to_human(1234567890)
      "1.2B"
  """
  def number_to_human(number) when is_number(number) do
    cond do
      number >= 1_000_000_000 -> "#{Float.round(number / 1_000_000_000, 1)}B"
      number >= 1_000_000 -> "#{Float.round(number / 1_000_000, 1)}M"
      number >= 1_000 -> "#{Float.round(number / 1_000, 1)}K"
      true -> "#{number}"
    end
  end

  def number_to_human(_), do: "0"
end
