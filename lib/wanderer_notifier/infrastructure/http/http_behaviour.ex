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

  @callback get(url(), headers(), opts()) :: response()
  @callback post(url(), body(), headers(), opts()) :: response()
  @callback post_json(url(), map(), headers(), opts()) :: response()
  @callback put(url(), body(), headers(), opts()) :: response()
  @callback delete(url(), headers(), opts()) :: response()
  @callback request(method(), url(), headers(), body() | nil, opts()) :: response()
  @callback get_killmail(integer(), String.t()) :: response()
end
