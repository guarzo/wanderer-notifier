defmodule WandererNotifier.Infrastructure.Http.HttpBehaviour do
  @moduledoc """
  Behaviour for HTTP clients to enable mocking in tests.
  """

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map()
  @type method :: :get | :post | :put | :delete | :head | :options
  @type response :: {:ok, %{status_code: integer(), body: term()}} | {:error, term()}

  @callback request(method(), url(), body() | nil, headers(), opts()) :: response()
  @callback get_killmail(integer(), String.t()) :: response()
end
