defmodule WandererNotifier.HttpClient.Behaviour do
  @moduledoc """
  Behaviour for HTTP clients
  """

  @type headers :: [{String.t(), String.t()}]
  @type url :: String.t()
  @type body :: String.t() | map()
  @type options :: keyword()
  @type response :: {:ok, map()} | {:error, term()}
  @type method :: :get | :post | :put | :delete | :head | :options

  @callback get(url :: url) :: response
  @callback get(url :: url, headers :: headers) :: response
  @callback get(url :: url, headers :: headers, options :: options) :: response
  @callback post(url :: url, body :: body, headers :: headers) :: response
  @callback post_json(url :: url, body :: body, headers :: headers, options :: options) ::
              response
  @callback request(
              method :: method,
              url :: url,
              headers :: headers,
              body :: body,
              options :: options
            ) ::
              response
  @callback handle_response(response :: term()) :: response
end
