defmodule WandererNotifier.MockZKillClient do
  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  @impl true
  def get_single_killmail(_kill_id), do: {:ok, %{}}

  @impl true
  def get_recent_kills(_limit), do: {:ok, []}

  @impl true
  def get_system_kills(_system_id, _limit), do: {:ok, []}

  @impl true
  def get_character_kills(_character_id, _limit, _page), do: {:ok, []}
end

defmodule WandererNotifier.MockESI do
  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  @impl true
  def get_alliance_info(_id), do: {:ok, %{}}

  @impl true
  def get_character(_id), do: {:ok, %{}}

  @impl true
  def get_character_info(_id), do: {:ok, %{}}

  @impl true
  def get_corporation_info(_id), do: {:ok, %{}}

  @impl true
  def get_killmail(_id, _hash), do: {:ok, %{}}

  @impl true
  def get_system(_id), do: {:ok, %{}}

  @impl true
  def get_system_info(_id), do: {:ok, %{}}

  @impl true
  def get_type(_id), do: {:ok, %{}}

  @impl true
  def get_type_info(_id), do: {:ok, %{}}
end

defmodule WandererNotifier.MockCacheHelpers do
  @behaviour WandererNotifier.Helpers.CacheHelpersBehaviour

  @impl true
  def get_cached_kills(_character_id), do: {:ok, []}

  @impl true
  def get_character_name(_id), do: {:ok, "Unknown"}

  @impl true
  def get_ship_name(_id), do: {:ok, "Unknown"}

  @impl true
  def get_tracked_characters, do: []
end

defmodule WandererNotifier.MockRepository do
  @behaviour WandererNotifier.Data.Cache.RepositoryBehaviour

  @impl true
  def delete(_key), do: :ok

  @impl true
  def exists?(_key), do: true

  @impl true
  def get(_key), do: nil

  @impl true
  def get_and_update(_key, _fun), do: {nil, :ok}

  @impl true
  def get_tracked_characters, do: []

  @impl true
  def put(_key, _value), do: :ok

  @impl true
  def set(_key, _value, _ttl), do: :ok
end

defmodule WandererNotifier.MockKillmailPersistence do
  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour

  @impl true
  def maybe_persist_killmail(_killmail), do: {:ok, :persisted}

  @impl true
  def persist_killmail(_killmail), do: {:ok, :persisted}
end

defmodule WandererNotifier.MockLogger do
  @behaviour WandererNotifier.Logger

  @impl true
  def debug(message), do: :ok
  def debug(message, metadata), do: :ok
  def info(message), do: :ok
  def info(message, metadata), do: :ok
  def warn(message), do: :ok
  def warn(message, metadata), do: :ok
  def error(message), do: :ok
  def error(message, metadata), do: :ok
  def api_debug(message), do: :ok
  def api_debug(message, metadata), do: :ok
  def api_info(message), do: :ok
  def api_info(message, metadata), do: :ok
  def api_warn(message), do: :ok
  def api_warn(message, metadata), do: :ok
  def api_error(message), do: :ok
  def api_error(message, metadata), do: :ok
  def processor_debug(message), do: :ok
  def processor_debug(message, metadata), do: :ok
  def processor_info(message), do: :ok
  def processor_info(message, metadata), do: :ok
  def processor_warn(message), do: :ok
  def processor_warn(message, metadata), do: :ok
  def processor_error(message), do: :ok
  def processor_error(message, metadata), do: :ok
  def cache_debug(message), do: :ok
  def cache_debug(message, metadata), do: :ok
  def cache_info(message), do: :ok
  def cache_info(message, metadata), do: :ok
  def cache_warn(message), do: :ok
  def cache_warn(message, metadata), do: :ok
  def cache_error(message), do: :ok
  def cache_error(message, metadata), do: :ok
  def persistence_debug(message), do: :ok
  def persistence_debug(message, metadata), do: :ok
  def persistence_info(message), do: :ok
  def persistence_info(message, metadata), do: :ok
  def persistence_warn(message), do: :ok
  def persistence_warn(message, metadata), do: :ok
  def persistence_error(message), do: :ok
  def persistence_error(message, metadata), do: :ok
  def scheduler_debug(message), do: :ok
  def scheduler_debug(message, metadata), do: :ok
  def scheduler_info(message), do: :ok
  def scheduler_info(message, metadata), do: :ok
  def scheduler_warn(message), do: :ok
  def scheduler_warn(message, metadata), do: :ok
  def scheduler_error(message), do: :ok
  def scheduler_error(message, metadata), do: :ok
  def kill_debug(message), do: :ok
  def kill_debug(message, metadata), do: :ok
  def kill_info(message), do: :ok
  def kill_info(message, metadata), do: :ok
  def kill_warn(message), do: :ok
  def kill_warn(message, metadata), do: :ok
  def kill_error(message), do: :ok
  def kill_error(message, metadata), do: :ok
end
