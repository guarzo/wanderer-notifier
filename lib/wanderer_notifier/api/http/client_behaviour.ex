defmodule WandererNotifier.Api.Http.ClientBehaviour do
  @moduledoc """
  Behaviour specification for HTTP client implementations.
  """

  @typep method :: String.t() | atom()
  @typep url :: String.t()
  @typep headers :: [{String.t(), String.t()}]
  @typep body :: String.t()
  @typep opts :: keyword()
  @typep response :: {:ok, map()} | {:error, any()}

  @callback get(url, headers, opts) :: response
  @callback post(url, body, headers, opts) :: response
  @callback post_json(url, map(), headers, opts) :: response
  @callback put(url, body, headers, opts) :: response
  @callback delete(url, headers, opts) :: response
  @callback request(method, url, headers, body, opts) :: response
end
