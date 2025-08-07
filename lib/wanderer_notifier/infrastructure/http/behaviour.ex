defmodule WandererNotifier.Infrastructure.Http.Behaviour do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This allows for easy mocking in tests and swapping HTTP implementations.
  """

  @type method :: :get | :post | :put | :patch | :delete | :head | :options
  @type url :: String.t()
  @type body :: any()
  @type headers :: [{String.t(), String.t()}]
  @type opts :: keyword()

  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Makes an HTTP request.

  ## Parameters
    - method: HTTP method (:get, :post, etc.)
    - url: Full URL to request
    - body: Request body (can be nil for GET requests)
    - headers: List of header tuples
    - opts: Additional options (timeout, service, auth, etc.)
    
  ## Returns
    - {:ok, %{status_code: integer(), headers: list(), body: any()}}
    - {:error, reason}
  """
  @callback request(method(), url(), body(), headers(), opts()) :: response()
end
