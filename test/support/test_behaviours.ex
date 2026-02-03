defmodule WandererNotifier.Domains.Notifications.Config.Behaviour do
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

defmodule WandererNotifier.Test.TrackingBehaviour do
  @moduledoc """
  Test behaviour definition for entity tracking services (characters and systems).
  """
  @callback is_tracked?(non_neg_integer()) :: {:ok, boolean()} | {:error, any()}
end

defmodule WandererNotifier.Infrastructure.Adapters.ESI.Service.Behaviour do
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

defmodule WandererNotifier.Domains.Killmail.Cache.Behaviour do
  @moduledoc """
  Behaviour for killmail cache operations
  """
  @callback get_kill(integer()) :: {:ok, map()} | {:error, term()}
  @callback store_kill(integer(), map()) :: :ok | {:error, term()}
  @callback mget(list(integer())) :: {:ok, map()} | {:error, term()}
end

defmodule WandererNotifier.System.Behaviour do
  @moduledoc """
  Behaviour for system operations
  """
  @callback is_tracked?(integer()) :: {:ok, boolean()} | {:error, any()}
end

defmodule WandererNotifier.Character.Behaviour do
  @moduledoc """
  Behaviour for character operations
  """
  @callback is_tracked?(integer()) :: {:ok, boolean()} | {:error, any()}
end

defmodule WandererNotifier.Deduplication.Behaviour do
  @moduledoc """
  Behaviour for deduplication operations
  """
  @callback check(atom(), integer()) :: {:ok, :new | :duplicate} | {:error, term()}
end

defmodule WandererNotifier.Shared.Config.Behaviour do
  @moduledoc """
  Behaviour for configuration operations
  """
  @callback get_config() :: {:ok, map()} | {:error, term()}
  @callback notifications_enabled?() :: boolean()
  @callback kill_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback get_notification_setting(atom(), atom()) ::
              {:ok, boolean()} | {:error, :unknown_setting}
  @callback deduplication_module() :: module()
  @callback system_track_module() :: module()
  @callback character_track_module() :: module()
end

defmodule WandererNotifier.Dispatcher.Behaviour do
  @moduledoc """
  Behaviour for notification dispatching
  """
  @callback dispatch(map()) :: :ok | {:error, term()}
end

defmodule WandererNotifier.Infrastructure.Cache.Behaviour do
  @moduledoc """
  Behaviour for cache operations
  """
  @callback get(String.t()) :: {:ok, term()} | {:error, :not_found}
  @callback put(String.t(), term()) :: :ok | {:error, term()}
  @callback put(String.t(), term(), pos_integer() | :infinity | nil) :: :ok | {:error, term()}
  @callback delete(String.t()) :: :ok
end

defmodule WandererNotifier.Test.MockDeduplicationBehaviour do
  @moduledoc """
  Test behaviour for deduplication operations
  """
  @callback check(atom(), term()) :: {:ok, :new | :duplicate} | {:error, term()}
  @callback check_and_record(atom(), term()) :: {:ok, :new | :duplicate} | {:error, term()}
end

defmodule WandererNotifier.Domains.Notifications.KillmailNotificationBehaviour do
  @moduledoc """
  Behaviour for killmail notification creation
  """
  @callback create(map()) :: map()
end

defmodule WandererNotifier.Domains.Tracking.StaticInfoBehaviour do
  @moduledoc """
  Behaviour for static info enrichment
  """
  @callback enrich_system(map()) :: map()
end

defmodule WandererNotifier.Contexts.ApiContextBehaviour do
  @moduledoc """
  Behaviour for API context operations
  """
  @callback get_tracked_systems() :: {:ok, list()} | {:error, term()}
  @callback get_tracked_characters() :: {:ok, list()} | {:error, term()}
end

defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.NotifierBehaviour do
  @moduledoc """
  Behaviour for Discord notifier operations
  """
  @callback send_kill_notification(map(), atom(), keyword()) :: :ok | {:error, term()}
  @callback send_discord_embed(map()) :: :ok | {:error, term()}
end
