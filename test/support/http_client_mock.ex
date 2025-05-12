defmodule WandererNotifier.Test.Support.HttpClientMock do
  @moduledoc """
  A module that implements the WandererNotifier.HttpClient.Behaviour for testing.
  This helps fix the issues with Mox expecting get/3 instead of get/2.
  """

  # Define the behavior callback
  @callback get(url :: String.t(), headers :: list(), options :: keyword()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Mock implementation of the get/1 function.
  This is the function missing in tests.
  """
  def get(url) do
    # Call get/2 with empty headers
    get(url, [])
  end

  @doc """
  Mock implementation of the get/3 function with options.
  This is the function missing in tests.
  """
  def get(url, headers, _options \\ []) do
    # Just delegate to get/2 for simplicity
    get(url, headers)
  end

  @doc """
  Mock implementation of the post/3 function.
  """
  def post(_url, _body, _headers) do
    # Default implementation that will be overridden by Mox
    {:ok, %{status_code: 200, body: %{mock: true}}}
  end

  @doc """
  Mock implementation of the post_json/4 function.
  """
  def post_json(_url, _body, _headers, _options \\ []) do
    # Default implementation that will be overridden by Mox
    {:ok, %{status_code: 200, body: %{mock: true}}}
  end

  @doc """
  Mock implementation of the request/5 function.
  """
  def request(_method, _url, _headers \\ [], _body \\ nil, _opts \\ []) do
    # Default implementation that will be overridden by Mox
    {:ok, %{status_code: 200, body: %{mock: true}}}
  end

  @doc """
  Mock implementation of the handle_response/1 function.
  """
  def handle_response({:ok, response}) do
    {:ok, response}
  end

  def handle_response({:error, reason}) do
    {:error, reason}
  end
end
