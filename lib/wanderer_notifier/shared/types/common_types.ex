defmodule WandererNotifier.Shared.Types.CommonTypes do
  @moduledoc """
  Common type definitions used across WandererNotifier.

  This module consolidates frequently used type definitions to ensure
  consistency and reduce duplication across the codebase.
  """

  # ── HTTP Related Types ──────────────────────────────────────────────────────

  @typedoc "HTTP URL string"
  @type url :: String.t()

  @typedoc "HTTP headers as key-value pairs"
  @type headers :: list({String.t(), String.t()})

  @typedoc "HTTP request body"
  @type body :: String.t() | map() | nil

  @typedoc "HTTP method"
  @type method :: :get | :post | :put | :delete | :head | :options | :patch

  @typedoc "HTTP response structure"
  @type http_response :: {:ok, map()} | {:error, term()}

  @typedoc "HTTP status code"
  @type status_code :: pos_integer()

  # ── Common Data Types ───────────────────────────────────────────────────────

  @typedoc "Generic ID type (integer)"
  @type id :: pos_integer()

  @typedoc "String-based identifier"
  @type string_id :: String.t()

  @typedoc "Timestamp in Unix seconds"
  @type timestamp :: non_neg_integer()

  @typedoc "Timestamp in ISO 8601 format"
  @type iso_timestamp :: String.t()

  # ── EVE Online Types ────────────────────────────────────────────────────────

  @typedoc "EVE character ID"
  @type character_id :: pos_integer()

  @typedoc "EVE corporation ID"
  @type corporation_id :: pos_integer()

  @typedoc "EVE alliance ID"
  @type alliance_id :: pos_integer()

  @typedoc "EVE system ID"
  @type system_id :: pos_integer()

  @typedoc "EVE killmail ID"
  @type killmail_id :: pos_integer()

  @typedoc "EVE ship type ID"
  @type ship_type_id :: pos_integer()

  @typedoc "Security status (0.0 to 1.0)"
  @type security_status :: float()

  # ── Result Types ────────────────────────────────────────────────────────────

  @typedoc "Standard success/error result tuple"
  @type result(success_type) :: {:ok, success_type} | {:error, term()}

  @typedoc "Standard success/error result tuple with atom error"
  @type result(success_type, error_type) :: {:ok, success_type} | {:error, error_type}

  @typedoc "Generic success/error result"
  @type generic_result :: result(term())

  # ── Configuration Types ─────────────────────────────────────────────────────

  @typedoc "Configuration key"
  @type config_key :: atom() | String.t()

  @typedoc "Configuration value"
  @type config_value :: term()

  @typedoc "Configuration map"
  @type config :: %{config_key() => config_value()}

  # ── Cache Types ─────────────────────────────────────────────────────────────

  @typedoc "Cache key"
  @type cache_key :: String.t()

  @typedoc "Cache TTL in seconds"
  @type cache_ttl :: pos_integer()

  @typedoc "Cache operation result"
  @type cache_result :: result(term())

  # ── Event Types ─────────────────────────────────────────────────────────────

  @typedoc "Event source"
  @type event_source :: :websocket | :sse | :http | :internal

  @typedoc "Event type identifier"
  @type event_type :: String.t()

  @typedoc "Event unique identifier"
  @type event_id :: String.t()

  # ── Notification Types ──────────────────────────────────────────────────────

  @typedoc "Notification type"
  @type notification_type :: :system | :character | :killmail

  @typedoc "Discord embed color (hex integer)"
  @type embed_color :: non_neg_integer()

  # ── Validation Types ────────────────────────────────────────────────────────

  @typedoc "Validation result"
  @type validation_result :: :ok | {:error, String.t()}

  @typedoc "Validation errors list"
  @type validation_errors :: [String.t()]
end
