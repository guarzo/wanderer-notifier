defmodule WandererNotifier.Infrastructure.Cache.Keys do
  @moduledoc """
  Cache key generation for consistent naming patterns.

  ## Key Naming Conventions

  Keys follow the pattern `namespace:type:identifier` where:
  - `namespace` groups related data (e.g., `esi`, `tracking`, `map`)
  - `type` identifies the data type (e.g., `character`, `system`)
  - `identifier` is the unique ID for the specific record

  ## Examples

      iex> Keys.character(12345)
      "esi:character:12345"

      iex> Keys.tracked_system("J123456")
      "tracking:system:J123456"

      iex> Keys.map_systems()
      "map:systems"
  """

  # ============================================================================
  # ESI-related keys (external API data)
  # ============================================================================

  @doc "Generates cache key for ESI character data."
  @spec character(integer() | String.t()) :: String.t()
  def character(id), do: "esi:character:#{id}"

  @doc "Generates cache key for ESI corporation data."
  @spec corporation(integer() | String.t()) :: String.t()
  def corporation(id), do: "esi:corporation:#{id}"

  @doc "Generates cache key for ESI alliance data."
  @spec alliance(integer() | String.t()) :: String.t()
  def alliance(id), do: "esi:alliance:#{id}"

  @doc "Generates cache key for ESI system data."
  @spec system(integer() | String.t()) :: String.t()
  def system(id), do: "esi:system:#{id}"

  @doc "Generates cache key for ESI system name data."
  @spec system_name(integer() | String.t()) :: String.t()
  def system_name(id), do: "esi:system_name:#{id}"

  @doc "Generates cache key for ESI universe type data."
  @spec universe_type(integer() | String.t()) :: String.t()
  def universe_type(id), do: "esi:universe_type:#{id}"

  @doc "Generates cache key for ESI item price data."
  @spec item_price(integer() | String.t()) :: String.t()
  def item_price(id), do: "esi:item_price:#{id}"

  # ============================================================================
  # Killmail-related keys
  # ============================================================================

  @doc "Generates cache key for killmail data."
  @spec killmail(integer() | String.t()) :: String.t()
  def killmail(id), do: "data:killmail:#{id}"

  @doc "Generates cache key for WebSocket deduplication."
  @spec websocket_dedup(integer() | String.t()) :: String.t()
  def websocket_dedup(killmail_id), do: "websocket_dedup:#{killmail_id}"

  # ============================================================================
  # Notification keys
  # ============================================================================

  @doc "Generates cache key for notification deduplication."
  @spec notification_dedup(String.t()) :: String.t()
  def notification_dedup(key), do: "notification:dedup:#{key}"

  # ============================================================================
  # Map-related keys
  # ============================================================================

  @doc "Returns cache key for map systems data."
  @spec map_systems() :: String.t()
  def map_systems, do: "map:systems"

  @doc "Returns cache key for map characters data."
  @spec map_characters() :: String.t()
  def map_characters, do: "map:characters"

  @doc "Generates cache key for map state data."
  @spec map_state(String.t()) :: String.t()
  def map_state(map_slug), do: "map:state:#{map_slug}"

  @doc "Returns cache key for map subscription data."
  @spec map_subscription_data() :: String.t()
  def map_subscription_data, do: "map:subscription_data"

  # ============================================================================
  # Tracking keys for individual lookups (O(1) performance)
  # ============================================================================

  @doc "Generates cache key for tracked character data."
  @spec tracked_character(integer() | String.t()) :: String.t()
  def tracked_character(id), do: "tracking:character:#{id}"

  @doc "Generates cache key for tracked system data."
  @spec tracked_system(integer() | String.t()) :: String.t()
  def tracked_system(id), do: "tracking:system:#{id}"

  @doc "Returns cache key for tracked systems list."
  @spec tracked_systems_list() :: String.t()
  def tracked_systems_list, do: "tracking:systems_list"

  @doc "Returns cache key for tracked characters list."
  @spec tracked_characters_list() :: String.t()
  def tracked_characters_list, do: "tracking:characters_list"

  # ============================================================================
  # Domain-specific data keys (using entity namespace for clarity)
  # ============================================================================

  @doc "Generates cache key for corporation data."
  @spec corporation_data(integer() | String.t()) :: String.t()
  def corporation_data(id), do: "entity:corporation:#{id}"

  @doc "Generates cache key for ship type data."
  @spec ship_type(integer() | String.t()) :: String.t()
  def ship_type(id), do: "entity:ship_type:#{id}"

  @doc "Generates cache key for solar system data."
  @spec solar_system(integer() | String.t()) :: String.t()
  def solar_system(id), do: "entity:solar_system:#{id}"

  # ============================================================================
  # Scheduler keys
  # ============================================================================

  @doc "Generates cache key for scheduler primed state."
  @spec scheduler_primed(String.t() | atom()) :: String.t()
  def scheduler_primed(scheduler_name), do: "scheduler:primed:#{scheduler_name}"

  @doc "Generates cache key for scheduler data."
  @spec scheduler_data(String.t() | atom()) :: String.t()
  def scheduler_data(scheduler_name), do: "scheduler:data:#{scheduler_name}"

  # ============================================================================
  # Status and reporting keys
  # ============================================================================

  @doc "Generates cache key for status report data."
  @spec status_report(integer() | String.t()) :: String.t()
  def status_report(minute), do: "status_report:#{minute}"

  # ============================================================================
  # Janice appraisal keys
  # ============================================================================

  @doc "Generates cache key for Janice appraisal data."
  @spec janice_appraisal(String.t() | integer()) :: String.t()
  def janice_appraisal(hash), do: "janice:appraisal:#{hash}"

  # ============================================================================
  # License validation keys
  # ============================================================================

  @doc "Returns cache key for license validation result."
  @spec license_validation() :: String.t()
  def license_validation, do: "license:validation"

  # ============================================================================
  # Generic helper for custom keys
  # ============================================================================

  @doc """
  Generates a custom cache key with the given prefix and suffix.

  ## Examples

      iex> Keys.custom("search", "inventory_type_query")
      "search:inventory_type_query"
  """
  @spec custom(String.t(), String.t()) :: String.t()
  def custom(prefix, suffix), do: "#{prefix}:#{suffix}"
end
