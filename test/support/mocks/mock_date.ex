defmodule WandererNotifier.MockDate do
  @moduledoc """
  Mock implementation of Date functions for testing.
  """
  @behaviour WandererNotifier.DateBehaviour

  @impl true
  def now do
    DateTime.utc_now()
  end

  @impl true
  def utc_today do
    Date.utc_today()
  end

  @impl true
  def day_of_week(date) do
    Date.day_of_week(date)
  end
end
