defmodule WandererNotifier.HttpClient.Behaviour do
  @moduledoc """
  Behaviour for HTTP client operations.
  Defines the contract that HTTP client implementations must follow.
  """

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map()
  @type method :: :get | :post | :put | :delete | :head | :options
  @type response :: {:ok, %{status_code: integer(), body: term()}} | {:error, term()}

  @callback get(url :: url, headers :: headers) :: response
  @callback get(url :: url, headers :: headers, opts :: opts) :: response
  @callback post(url :: url, body :: body, headers :: headers) :: response
  @callback post_json(url :: url, body :: body, headers :: headers, opts :: opts) :: response
  @callback request(method :: method, url :: url, headers :: headers, body :: body, opts :: opts) ::
              response
  @callback handle_response(response :: term()) :: response
end
