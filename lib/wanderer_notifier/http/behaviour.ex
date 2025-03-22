defmodule WandererNotifier.HTTP.Behaviour do
  @moduledoc """
  Defines the behaviour for HTTP clients to enable mocking in tests.
  """

  @type headers :: [{String.t(), String.t()}]
  @type options :: Keyword.t()
  @type response :: %{status: integer(), body: String.t() | map(), headers: headers()}

  @callback get(url :: String.t(), headers :: headers(), options :: options()) ::
              {:ok, response()} | {:error, term()}

  @callback post(url :: String.t(), body :: term(), headers :: headers(), options :: options()) ::
              {:ok, response()} | {:error, term()}
end
