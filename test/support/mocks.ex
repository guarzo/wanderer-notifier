defmodule WandererNotifier.Mocks do
  @moduledoc """
  Defines mocks for external services used in tests.
  """

  # Import Mox to define mocks
  import Mox

  # Define the behavior for HTTP client
  defmodule HTTPClientBehavior do
    @callback get(String.t(), list(), list()) :: {:ok, map()} | {:error, any()}
    @callback post(String.t(), any(), list(), list()) :: {:ok, map()} | {:error, any()}
  end

  # Define the behavior for ESI service
  defmodule ESIServiceBehavior do
    @callback get_killmail(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_character_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_corporation_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_system_info(integer()) :: {:ok, map()} | {:error, any()}
  end

  # Mock implementations
  defmock(WandererNotifier.MockHTTPClient, for: HTTPClientBehavior)
  defmock(WandererNotifier.MockESIService, for: ESIServiceBehavior)
end
