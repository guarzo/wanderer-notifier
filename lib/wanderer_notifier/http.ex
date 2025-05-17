defmodule WandererNotifier.HTTP do
  @moduledoc """
  Behaviour for HTTP client operations.
  """

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type body :: String.t() | map()
  @type options :: keyword()
  @type response :: {:ok, %{status_code: integer(), body: term()}} | {:error, term()}

  @callback get(url()) :: response()
  @callback get(url(), headers()) :: response()
  @callback get(url(), headers(), options()) :: response()
  @callback post(url(), body(), headers()) :: response()
  @callback post_json(url(), body(), headers(), options()) :: response()
  @callback request(atom(), url(), headers(), body(), options()) :: response()
end
