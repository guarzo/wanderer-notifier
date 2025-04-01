defmodule WandererNotifier.DateBehaviour do
  @moduledoc """
  Behaviour for date-related functions.
  """

  @callback utc_today() :: Date.t()
  @callback day_of_week(Date.t()) :: non_neg_integer()
end
