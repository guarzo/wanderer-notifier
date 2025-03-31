defmodule WandererNotifier.Api.ZKill.WebSocketBehaviour do
  @moduledoc """
  Defines the behaviour for WebSocket operations to enable mocking in tests.
  """

  @callback start_link(url :: String.t() | Keyword.t()) :: {:ok, pid()} | {:error, term()}
  @callback send_frame(pid :: pid(), frame :: term()) :: :ok | {:error, term()}
  @callback cast(pid :: pid(), message :: term()) :: :ok
end
