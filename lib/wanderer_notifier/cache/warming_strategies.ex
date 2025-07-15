defmodule WandererNotifier.Cache.WarmingStrategies do
  @moduledoc """
  Cache warming strategies for critical data pre-loading.

  This module defines and implements various cache warming strategies
  to ensure critical data is available in cache before it's needed.

  ## Strategy Types

  - **Startup Strategies**: Executed during application startup
  - **Periodic Strategies**: Executed at regular intervals
  - **Event-driven Strategies**: Executed in response to specific events

  ## Built-in Strategies

  - `:recent_characters` - Warm recently active characters
  - `:priority_systems` - Warm priority wormhole systems
  - `:active_corporations` - Warm active corporations
  - `:map_systems` - Warm systems from current map data
  - `:frequent_alliances` - Warm frequently accessed alliances

  ## Custom Strategies

  You can define custom strategies by implementing the strategy callback:

  ```elixir
  defmodule MyWarmingStrategy do
    @behaviour WandererNotifier.Cache.WarmingStrategies
    
    def execute_strategy(:my_strategy) do
      {:ok, [
        {:character, 123456},
        {:system, 30000142}
      ]}
    end
  end
  ```
  """

  require Logger

  @type warming_item :: {atom(), term()}
  @type strategy_result :: {:ok, [warming_item()]} | {:error, term()}

  @callback execute_strategy(atom()) :: strategy_result()

  @doc """
  Executes a warming strategy by name.

  ## Parameters
  - strategy_name: Name of the strategy to execute

  ## Returns
  {:ok, warming_items} | {:error, reason}
  """
  @spec execute_strategy(atom()) :: strategy_result()
  def execute_strategy(strategy_name) do
    strategies = %{
      recent_characters: &warm_recent_characters/0,
      priority_systems: &warm_priority_systems/0,
      active_corporations: &warm_active_corporations/0,
      map_systems: &warm_map_systems/0,
      frequent_alliances: &warm_frequent_alliances/0,
      critical_startup: &warm_critical_startup_data/0,
      killmail_entities: &warm_killmail_entities/0,
      notification_dependencies: &warm_notification_dependencies/0
    }

    case Map.get(strategies, strategy_name) do
      nil -> {:error, {:unknown_strategy, strategy_name}}
      strategy_fn -> strategy_fn.()
    end
  end

  @doc """
  Gets the list of startup strategies.

  These strategies are executed during application startup to ensure
  critical data is available immediately.

  ## Returns
  List of strategy names
  """
  @spec get_startup_strategies() :: [atom()]
  def get_startup_strategies do
    [
      :critical_startup,
      :priority_systems,
      :recent_characters,
      :active_corporations
    ]
  end

  @doc """
  Gets the list of periodic strategies.

  These strategies are executed at regular intervals to refresh
  cache data and maintain performance.

  ## Returns
  List of strategy names
  """
  @spec get_periodic_strategies() :: [atom()]
  def get_periodic_strategies do
    [
      :recent_characters,
      :map_systems,
      :frequent_alliances,
      :killmail_entities,
      :notification_dependencies
    ]
  end

  @doc """
  Gets strategy configuration and metadata.

  ## Parameters
  - strategy_name: Name of the strategy

  ## Returns
  Map with strategy configuration
  """
  @spec get_strategy_config(atom()) :: map()
  def get_strategy_config(strategy_name) do
    strategy_configs = %{
      recent_characters: %{
        description: "Warm recently active characters",
        frequency: :high,
        expected_items: 50,
        timeout: 30_000
      },
      priority_systems: %{
        description: "Warm priority wormhole systems",
        frequency: :medium,
        expected_items: 100,
        timeout: 60_000
      },
      active_corporations: %{
        description: "Warm active corporations",
        frequency: :medium,
        expected_items: 25,
        timeout: 30_000
      },
      map_systems: %{
        description: "Warm systems from current map data",
        frequency: :high,
        expected_items: 200,
        timeout: 120_000
      },
      frequent_alliances: %{
        description: "Warm frequently accessed alliances",
        frequency: :low,
        expected_items: 10,
        timeout: 30_000
      },
      critical_startup: %{
        description: "Warm critical startup data",
        frequency: :startup_only,
        expected_items: 20,
        timeout: 60_000
      },
      killmail_entities: %{
        description: "Warm entities from recent killmails",
        frequency: :high,
        expected_items: 75,
        timeout: 45_000
      },
      notification_dependencies: %{
        description: "Warm notification dependency data",
        frequency: :medium,
        expected_items: 30,
        timeout: 30_000
      }
    }

    Map.get(strategy_configs, strategy_name, %{
      description: "Unknown strategy",
      frequency: :unknown,
      expected_items: 0,
      timeout: 30_000
    })
  end

  # Strategy implementations

  defp warm_recent_characters do
    try do
      # Get recent characters from various sources
      characters = []

      # From recent killmails
      characters = characters ++ get_recent_killmail_characters()

      # From map activity
      characters = characters ++ get_recent_map_characters()

      # From notifications
      characters = characters ++ get_recent_notification_characters()

      # Remove duplicates and limit
      unique_characters =
        characters
        |> Enum.uniq()
        |> Enum.take(50)
        |> Enum.map(&{:character, &1})

      Logger.debug("Warming #{length(unique_characters)} recent characters")
      {:ok, unique_characters}
    rescue
      error ->
        Logger.error("Failed to get recent characters: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_priority_systems do
    try do
      # Get priority systems from configuration and map data
      systems = []

      # From map configuration
      systems = systems ++ get_priority_map_systems()

      # From recent activity
      systems = systems ++ get_active_systems()

      # From wormhole connections
      systems = systems ++ get_connected_systems()

      # Remove duplicates and limit
      unique_systems =
        systems
        |> Enum.uniq()
        |> Enum.take(100)
        |> Enum.map(&{:system, &1})

      Logger.debug("Warming #{length(unique_systems)} priority systems")
      {:ok, unique_systems}
    rescue
      error ->
        Logger.error("Failed to get priority systems: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_active_corporations do
    try do
      # Get active corporations from recent activity
      corporations = []

      # From recent killmails
      corporations = corporations ++ get_recent_killmail_corporations()

      # From map activity
      corporations = corporations ++ get_active_map_corporations()

      # From character data
      corporations = corporations ++ get_character_corporations()

      # Remove duplicates and limit
      unique_corporations =
        corporations
        |> Enum.uniq()
        |> Enum.take(25)
        |> Enum.map(&{:corporation, &1})

      Logger.debug("Warming #{length(unique_corporations)} active corporations")
      {:ok, unique_corporations}
    rescue
      error ->
        Logger.error("Failed to get active corporations: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_map_systems do
    try do
      # Get systems from current map data
      systems = get_current_map_systems()

      # Limit to reasonable number
      limited_systems =
        systems
        |> Enum.take(200)
        |> Enum.map(&{:system, &1})

      Logger.debug("Warming #{length(limited_systems)} map systems")
      {:ok, limited_systems}
    rescue
      error ->
        Logger.error("Failed to get map systems: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_frequent_alliances do
    try do
      # Get frequently accessed alliances
      alliances = []

      # From recent killmails
      alliances = alliances ++ get_recent_killmail_alliances()

      # From corporation data
      alliances = alliances ++ get_corporation_alliances()

      # From cached data statistics
      alliances = alliances ++ get_frequent_cached_alliances()

      # Remove duplicates and limit
      unique_alliances =
        alliances
        |> Enum.uniq()
        |> Enum.take(10)
        |> Enum.map(&{:alliance, &1})

      Logger.debug("Warming #{length(unique_alliances)} frequent alliances")
      {:ok, unique_alliances}
    rescue
      error ->
        Logger.error("Failed to get frequent alliances: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_critical_startup_data do
    try do
      # Critical data needed immediately on startup
      items = []

      # Essential systems
      items = items ++ get_essential_systems()

      # Core characters
      items = items ++ get_core_characters()

      # Important corporations
      items = items ++ get_important_corporations()

      Logger.debug("Warming #{length(items)} critical startup items")
      {:ok, items}
    rescue
      error ->
        Logger.error("Failed to get critical startup data: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_killmail_entities do
    try do
      # Get entities from recent killmails
      entities = []

      # Characters from recent kills
      entities = entities ++ (get_recent_killmail_characters() |> Enum.map(&{:character, &1}))

      # Corporations from recent kills
      entities = entities ++ (get_recent_killmail_corporations() |> Enum.map(&{:corporation, &1}))

      # Systems from recent kills
      entities = entities ++ (get_recent_killmail_systems() |> Enum.map(&{:system, &1}))

      # Remove duplicates and limit
      unique_entities =
        entities
        |> Enum.uniq()
        |> Enum.take(75)

      Logger.debug("Warming #{length(unique_entities)} killmail entities")
      {:ok, unique_entities}
    rescue
      error ->
        Logger.error("Failed to get killmail entities: #{inspect(error)}")
        {:error, error}
    end
  end

  defp warm_notification_dependencies do
    try do
      # Get entities needed for notifications
      entities = []

      # Characters that generate notifications
      entities = entities ++ (get_notification_characters() |> Enum.map(&{:character, &1}))

      # Systems for notification context
      entities = entities ++ (get_notification_systems() |> Enum.map(&{:system, &1}))

      # Remove duplicates and limit
      unique_entities =
        entities
        |> Enum.uniq()
        |> Enum.take(30)

      Logger.debug("Warming #{length(unique_entities)} notification dependencies")
      {:ok, unique_entities}
    rescue
      error ->
        Logger.error("Failed to get notification dependencies: #{inspect(error)}")
        {:error, error}
    end
  end

  # Helper functions - these would integrate with actual data sources

  defp get_recent_killmail_characters do
    # In a real implementation, this would query recent killmails
    # For now, return some sample data
    [123_456, 234_567, 345_678, 456_789, 567_890]
  end

  defp get_recent_map_characters do
    # Query map service for recent character activity
    []
  end

  defp get_recent_notification_characters do
    # Query notification system for recent character activity
    []
  end

  defp get_priority_map_systems do
    # Get priority systems from map configuration
    [30_000_142, 30_000_143, 30_000_144, 30_000_145]
  end

  defp get_active_systems do
    # Get systems with recent activity
    []
  end

  defp get_connected_systems do
    # Get systems connected via wormholes
    []
  end

  defp get_recent_killmail_corporations do
    # Get corporations from recent killmails
    [98_765, 98_764, 98_763, 98_762]
  end

  defp get_active_map_corporations do
    # Get corporations active on maps
    []
  end

  defp get_character_corporations do
    # Get corporations of cached characters
    []
  end

  defp get_current_map_systems do
    # Get all systems from current map data
    [30_000_142, 30_000_143, 30_000_144, 30_000_145, 30_000_146]
  end

  defp get_recent_killmail_alliances do
    # Get alliances from recent killmails
    [99_999, 99_998, 99_997]
  end

  defp get_corporation_alliances do
    # Get alliances of cached corporations
    []
  end

  defp get_frequent_cached_alliances do
    # Get alliances frequently accessed from cache
    []
  end

  defp get_essential_systems do
    # Critical systems needed for startup
    [{:system, 30_000_142}, {:system, 30_000_143}]
  end

  defp get_core_characters do
    # Core characters needed for startup
    [{:character, 123_456}, {:character, 234_567}]
  end

  defp get_important_corporations do
    # Important corporations needed for startup
    [{:corporation, 98_765}, {:corporation, 98_764}]
  end

  defp get_recent_killmail_systems do
    # Get systems from recent killmails
    [30_000_142, 30_000_143, 30_000_144]
  end

  defp get_notification_characters do
    # Get characters that generate notifications
    [123_456, 234_567]
  end

  defp get_notification_systems do
    # Get systems relevant for notifications
    [30_000_142, 30_000_143]
  end
end
