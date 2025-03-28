defmodule WandererNotifier.MockZKillClient do
  @moduledoc """
  Mock implementation of the ZKillboard client for testing.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour
end

defmodule WandererNotifier.MockESI do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour
end

defmodule WandererNotifier.MockCacheHelpers do
  @moduledoc """
  Mock implementation of the cache helpers for testing.
  """

  @behaviour WandererNotifier.Helpers.CacheHelpersBehaviour
end

defmodule WandererNotifier.MockRepository do
  @moduledoc """
  Mock implementation of the repository for testing.
  """

  @behaviour WandererNotifier.Data.Cache.RepositoryBehaviour
end

defmodule WandererNotifier.MockKillmailPersistence do
  @moduledoc """
  Mock implementation of the killmail persistence service for testing.
  """

  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour
end

defmodule WandererNotifier.MockLogger do
  @moduledoc """
  Mock implementation of the logger for testing.
  """

  @behaviour WandererNotifier.Logger
end
