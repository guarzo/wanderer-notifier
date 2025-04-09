defmodule WandererNotifier.Resources.ApiBehaviour do
  @moduledoc """
  Behaviour specification for the Resources API.

  This is primarily used for mocking in tests.
  """

  @callback read(query :: any()) :: {:ok, list()} | {:error, any()}
end
