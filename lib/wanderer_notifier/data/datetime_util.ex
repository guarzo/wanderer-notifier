defmodule WandererNotifier.Data.DateTimeUtil do
  @moduledoc """
  Utility functions for parsing and formatting datetime values consistently across the application.
  """

  @doc """
  Safely parses an ISO 8601 datetime string into a DateTime struct.

  ## Parameters
    - `datetime` - Can be a string in ISO 8601 format, a DateTime struct, or nil

  ## Returns
    - A DateTime struct if parsing was successful
    - The original DateTime if a DateTime was passed
    - nil if parsing failed or nil was passed

  ## Examples
      iex> parse_datetime("2023-05-01T15:30:45Z")
      ~U[2023-05-01 15:30:45Z]

      iex> parse_datetime(~U[2023-05-01 15:30:45Z])
      ~U[2023-05-01 15:30:45Z]

      iex> parse_datetime(nil)
      nil

      iex> parse_datetime("invalid")
      nil
  """
  @spec parse_datetime(String.t() | DateTime.t() | nil) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil
  def parse_datetime(%DateTime{} = dt), do: dt

  def parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, datetime, _} -> datetime
      _error -> nil
    end
  end

  def parse_datetime(_), do: nil
end
