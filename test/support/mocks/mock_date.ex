defmodule WandererNotifier.MockDate do
  @moduledoc """
  Mock implementation of Date functions for testing.
  """

  def utc_today do
    Date.utc_today()
  end

  def day_of_week(date) do
    Date.day_of_week(date)
  end
end
