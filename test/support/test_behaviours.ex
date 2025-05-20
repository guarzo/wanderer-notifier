defmodule WandererNotifier.Notifications.Config.Behaviour do
  @moduledoc """
  Behaviour for notifications configuration
  """
  @callback get_notification_setting(atom(), atom()) :: boolean()
  @callback get_config() :: map()
end

defmodule WandererNotifier.Test.DeduplicationBehaviour do
  @moduledoc """
  Test behaviour definition for deduplication services.
  """
  @callback check(:kill, String.t()) :: {:ok, :duplicate | :new} | {:error, term()}
  @callback clear_key(:kill, String.t()) :: {:ok, :cleared} | {:error, term()}
end

defmodule WandererNotifier.Test.ConfigBehaviour do
  @moduledoc """
  Test behaviour definition for configuration services.
  """
  @callback get_notification_setting(:kill, :enabled) :: boolean()
  @callback get_config() :: map()
end

defmodule WandererNotifier.Test.CharacterBehaviour do
  @moduledoc """
  Test behaviour definition for character tracking services.
  """
  @callback is_tracked?(String.t() | integer()) :: boolean()
end

defmodule WandererNotifier.Test.SystemBehaviour do
  @moduledoc """
  Test behaviour definition for system tracking services.
  """
  @callback is_tracked?(String.t() | integer()) :: boolean()
end

defmodule WandererNotifier.ESI.Service.Behaviour do
  @moduledoc """
  Behaviour for ESI service operations
  """
  @callback get_killmail(String.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_character_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_corporation_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_universe_type(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_system(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_system_kills(String.t(), Keyword.t()) :: {:ok, list(map())} | {:error, term()}
  @callback search(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
end

defmodule WandererNotifier.ESI.ClientBehaviour do
  @moduledoc """
  Behaviour for ESI client operations
  """
  @callback get_killmail(String.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_character_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_corporation_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_universe_type(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_system(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
end

defmodule WandererNotifier.Killmail.Cache.Behaviour do
  @moduledoc """
  Behaviour for killmail cache operations
  """
  @callback get_kill(integer()) :: {:ok, map()} | {:error, term()}
  @callback get_latest_killmails() :: list(map())
  @callback store_kill(integer(), map()) :: :ok | {:error, term()}
  @callback mget(list(integer())) :: {:ok, map()} | {:error, term()}
end

defmodule WandererNotifier.System.Behaviour do
  @moduledoc """
  Behaviour for system operations
  """
  @callback is_tracked?(integer()) :: boolean()
end

defmodule WandererNotifier.Character.Behaviour do
  @moduledoc """
  Behaviour for character operations
  """
  @callback is_tracked?(integer()) :: boolean()
end

defmodule WandererNotifier.Deduplication.Behaviour do
  @moduledoc """
  Behaviour for deduplication operations
  """
  @callback check(atom(), integer()) :: {:ok, :new | :duplicate} | {:error, term()}
end

defmodule WandererNotifier.Config.Behaviour do
  @moduledoc """
  Behaviour for configuration operations
  """
  @callback get_config() :: {:ok, map()} | {:error, term()}
  @callback notifications_enabled?() :: boolean()
  @callback kill_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback get_notification_setting(atom(), atom()) :: boolean()
end

defmodule WandererNotifier.Dispatcher.Behaviour do
  @moduledoc """
  Behaviour for notification dispatching
  """
  @callback dispatch(map()) :: :ok | {:error, term()}
end
