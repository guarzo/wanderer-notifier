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

  # Convenience callbacks for backward compatibility and test support
  @callback get(url(), headers(), opts()) :: response()
  @callback post(url(), body(), headers(), opts()) :: response()

  # Optional convenience callbacks (not required for all implementations)
  @optional_callbacks [put: 4, delete: 3, get_json: 3, post_json: 4]
  @callback put(url(), body(), headers(), opts()) :: response()
  @callback delete(url(), headers(), opts()) :: response()
  @callback get_json(url(), headers(), opts()) :: response()
  @callback post_json(url(), body(), headers(), opts()) :: response()
end
