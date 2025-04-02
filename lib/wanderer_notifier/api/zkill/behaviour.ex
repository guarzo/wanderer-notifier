defmodule WandererNotifier.Api.ZKill.Behaviour do
  @moduledoc """
  Behaviour specification for the ZKill service.
  """

  @callback get_killmail(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  @callback get_system_kills(String.t(), integer()) :: {:ok, list()} | {:error, any()}
end
