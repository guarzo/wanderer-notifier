ExUnit.start()

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP.Behaviour)
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockDiscord, for: WandererNotifier.Discord.Behaviour)
Mox.defmock(WandererNotifier.MockWebSocket, for: WandererNotifier.WebSocket.Behaviour)

# Needed for cache_helpers_test.exs
defmodule WandererNotifier.Data.Cache.RepositoryBehavior do
  @callback get(String.t()) :: any()
  @callback put(String.t(), any()) :: :ok
  @callback delete(String.t()) :: :ok
  @callback get_and_update(String.t(), (any() -> {any(), any()})) :: any()
end

Mox.defmock(WandererNotifier.Data.Cache.RepositoryMock,
  for: WandererNotifier.Data.Cache.RepositoryBehavior
)

# Set Mox global mode for integration tests where needed
Application.put_env(:mox, :verify_on_exit, true)
