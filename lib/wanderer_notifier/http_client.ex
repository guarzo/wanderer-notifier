defmodule WandererNotifier.HttpClient do
  @moduledoc """
  Behaviour for HTTP requests; used by ESI, ZKill, map clients, and mocks.
  """

  @type method :: :get | :post | :patch | :delete
  @callback request(
              method,
              url :: String.t(),
              headers :: list(),
              body :: term(),
              opts :: Keyword.t()
            ) ::
              {:ok, %{status: integer(), body: term()}}
              | {:error, term()}
end
