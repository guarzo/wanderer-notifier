defmodule WandererNotifier.Infrastructure.Cache.TtlConfig do
  @moduledoc """
  TTL (Time-To-Live) configuration for cache entries.

  ## TTL Values

  | Type              | TTL        | Use Case                              |
  |-------------------|------------|---------------------------------------|
  | `:character`      | 24 hours   | ESI character data                    |
  | `:corporation`    | 24 hours   | ESI corporation data                  |
  | `:alliance`       | 24 hours   | ESI alliance data                     |
  | `:system`         | 1 hour     | EVE system data (changes less often)  |
  | `:universe_type`  | 24 hours   | Item/ship type definitions            |
  | `:killmail`       | 30 minutes | Killmail processing deduplication     |
  | `:map_data`       | 1 hour     | Map system/character lists            |
  | `:item_price`     | 6 hours    | Market price data                     |
  | `:license`        | 20 minutes | License validation results            |
  | `:notification_dedup` | 30 minutes | Notification deduplication       |
  | `:health_check`   | 1 second   | Health check markers                  |

  ## Examples

      iex> TtlConfig.ttl(:character)
      86400000  # 24 hours in milliseconds

      iex> TtlConfig.ttl(:system)
      3600000   # 1 hour in milliseconds

      iex> TtlConfig.ttl(:unknown_type)
      86400000  # Falls back to default (24 hours)
  """

  # TTL configurations (in milliseconds)
  @character_ttl :timer.hours(24)
  @corporation_ttl :timer.hours(24)
  @alliance_ttl :timer.hours(24)
  @system_ttl :timer.hours(1)
  @universe_type_ttl :timer.hours(24)
  @killmail_ttl :timer.minutes(30)
  @map_data_ttl :timer.hours(1)
  @item_price_ttl :timer.hours(6)
  @license_ttl :timer.minutes(20)
  @notification_dedup_ttl :timer.minutes(30)
  @default_ttl :timer.hours(24)

  @type ttl_type ::
          :character
          | :corporation
          | :alliance
          | :system
          | :universe_type
          | :killmail
          | :map_data
          | :item_price
          | :license
          | :notification_dedup
          | :health_check
          | atom()

  @doc """
  Returns the TTL (in milliseconds) for the given data type.

  Falls back to the default TTL (24 hours) for unknown types.

  ## Examples

      iex> TtlConfig.ttl(:character)
      86400000

      iex> TtlConfig.ttl(:system)
      3600000

      iex> TtlConfig.ttl(:health_check)
      1000
  """
  @spec ttl(ttl_type()) :: pos_integer()
  def ttl(:character), do: @character_ttl
  def ttl(:corporation), do: @corporation_ttl
  def ttl(:alliance), do: @alliance_ttl
  def ttl(:system), do: @system_ttl
  def ttl(:universe_type), do: @universe_type_ttl
  def ttl(:killmail), do: @killmail_ttl
  def ttl(:map_data), do: @map_data_ttl
  def ttl(:item_price), do: @item_price_ttl
  def ttl(:license), do: @license_ttl
  def ttl(:notification_dedup), do: @notification_dedup_ttl
  def ttl(:health_check), do: :timer.seconds(1)
  def ttl(_), do: @default_ttl

  @doc """
  Returns the default TTL value (24 hours in milliseconds).
  """
  @spec default_ttl() :: pos_integer()
  def default_ttl, do: @default_ttl

  # ============================================================================
  # Deprecated: Use ttl/1 instead
  # ============================================================================

  @doc deprecated: "Use ttl(:character) instead"
  @spec character_ttl() :: pos_integer()
  def character_ttl, do: ttl(:character)

  @doc deprecated: "Use ttl(:corporation) instead"
  @spec corporation_ttl() :: pos_integer()
  def corporation_ttl, do: ttl(:corporation)

  @doc deprecated: "Use ttl(:alliance) instead"
  @spec alliance_ttl() :: pos_integer()
  def alliance_ttl, do: ttl(:alliance)

  @doc deprecated: "Use ttl(:system) instead"
  @spec system_ttl() :: pos_integer()
  def system_ttl, do: ttl(:system)

  @doc deprecated: "Use ttl(:universe_type) instead"
  @spec universe_type_ttl() :: pos_integer()
  def universe_type_ttl, do: ttl(:universe_type)

  @doc deprecated: "Use ttl(:killmail) instead"
  @spec killmail_ttl() :: pos_integer()
  def killmail_ttl, do: ttl(:killmail)

  @doc deprecated: "Use ttl(:map_data) instead"
  @spec map_data_ttl() :: pos_integer()
  def map_data_ttl, do: ttl(:map_data)

  @doc deprecated: "Use ttl(:item_price) instead"
  @spec item_price_ttl() :: pos_integer()
  def item_price_ttl, do: ttl(:item_price)

  @doc deprecated: "Use ttl(:license) instead"
  @spec license_ttl() :: pos_integer()
  def license_ttl, do: ttl(:license)

  @doc deprecated: "Use ttl(:notification_dedup) instead"
  @spec notification_dedup_ttl() :: pos_integer()
  def notification_dedup_ttl, do: ttl(:notification_dedup)
end
