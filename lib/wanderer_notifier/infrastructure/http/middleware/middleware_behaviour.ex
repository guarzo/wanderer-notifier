defmodule WandererNotifier.Infrastructure.Http.Middleware.MiddlewareBehaviour do
  @moduledoc """
  Behaviour definition for HTTP middleware components.

  Middleware components can intercept and modify HTTP requests and responses,
  implementing cross-cutting concerns like retry logic, rate limiting,
  circuit breaking, and telemetry.
  """

  @type request :: %{
          method: atom(),
          url: String.t(),
          headers: list({String.t(), String.t()}),
          body: String.t() | nil,
          opts: keyword()
        }

  @type response ::
          {:ok, %{status_code: integer(), body: term(), headers: list()}} | {:error, term()}

  @type next_fun :: (request() -> response())

  @doc """
  Called to process a request through the middleware chain.

  The middleware can:
  - Modify the request before passing to the next middleware
  - Handle the response before returning it
  - Implement retry logic, rate limiting, etc.
  - Short-circuit the chain by returning a response directly

  ## Parameters
  - `request` - The HTTP request structure
  - `next` - Function to call the next middleware in the chain

  ## Returns
  - `{:ok, response}` - Successful response
  - `{:error, reason}` - Error response
  """
  @callback call(request(), next_fun()) :: response()
end
