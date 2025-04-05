defmodule WandererNotifier.Utils.ListUtils do
  @moduledoc """
  Utility functions for working with lists and collections.
  """

  @doc """
  Ensures a value is converted to a list.

  Handles multiple input types:
  - nil -> Returns an empty list
  - List -> Returns the list unchanged
  - {:ok, list} -> Extracts and returns the list
  - {:error, _} -> Returns an empty list
  - Other values -> Returns an empty list

  ## Examples

      iex> ensure_list(nil)
      []

      iex> ensure_list([1, 2, 3])
      [1, 2, 3]

      iex> ensure_list({:ok, [1, 2, 3]})
      [1, 2, 3]

      iex> ensure_list({:error, "some error"})
      []
  """
  @spec ensure_list(list() | {:ok, list()} | {:error, any()} | nil) :: list()
  def ensure_list(nil), do: []
  def ensure_list(list) when is_list(list), do: list
  def ensure_list({:ok, list}) when is_list(list), do: list
  def ensure_list({:error, _}), do: []
  def ensure_list(_), do: []
end
