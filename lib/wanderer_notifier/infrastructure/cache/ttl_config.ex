defmodule WandererNotifier.Infrastructure.Cache.TtlConfig do
  @moduledoc """
  TTL (Time-To-Live) configuration for cache entries.

  Centralizes all TTL constants and provides a unified interface for
  retrieving TTL values based on data type.

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
  # TTL Constants (exposed for direct access if needed)
  # ============================================================================

  @doc "Returns the character TTL constant."
  @spec character_ttl() :: pos_integer()
  def character_ttl, do: @character_ttl

  @doc "Returns the corporation TTL constant."
  @spec corporation_ttl() :: pos_integer()
  def corporation_ttl, do: @corporation_ttl

  @doc "Returns the alliance TTL constant."
  @spec alliance_ttl() :: pos_integer()
  def alliance_ttl, do: @alliance_ttl

  @doc "Returns the system TTL constant."
  @spec system_ttl() :: pos_integer()
  def system_ttl, do: @system_ttl

  @doc "Returns the universe type TTL constant."
  @spec universe_type_ttl() :: pos_integer()
  def universe_type_ttl, do: @universe_type_ttl

  @doc "Returns the killmail TTL constant."
  @spec killmail_ttl() :: pos_integer()
  def killmail_ttl, do: @killmail_ttl

  @doc "Returns the map data TTL constant."
  @spec map_data_ttl() :: pos_integer()
  def map_data_ttl, do: @map_data_ttl

  @doc "Returns the item price TTL constant."
  @spec item_price_ttl() :: pos_integer()
  def item_price_ttl, do: @item_price_ttl

  @doc "Returns the license TTL constant."
  @spec license_ttl() :: pos_integer()
  def license_ttl, do: @license_ttl

  @doc "Returns the notification deduplication TTL constant."
  @spec notification_dedup_ttl() :: pos_integer()
  def notification_dedup_ttl, do: @notification_dedup_ttl
end
