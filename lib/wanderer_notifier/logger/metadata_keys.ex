defmodule WandererNotifier.Logger.MetadataKeys do
  @moduledoc """
  Centralized metadata key names for consistent logging across the application.
  """

  # ID Keys
  @doc "Key for killmail ID"
  def kill_id, do: :kill_id

  @doc "Key for system ID"
  def system_id, do: :system_id

  @doc "Key for character ID"
  def character_id, do: :character_id

  @doc "Key for corporation ID"
  def corporation_id, do: :corporation_id

  @doc "Key for alliance ID"
  def alliance_id, do: :alliance_id

  @doc "Key for type ID"
  def type_id, do: :type_id

  # HTTP/API Keys
  @doc "Key for URL"
  def url, do: :url

  @doc "Key for HTTP method"
  def method, do: :method

  @doc "Key for status code"
  def status_code, do: :status_code

  @doc "Key for duration in milliseconds"
  def duration_ms, do: :duration_ms

  @doc "Key for request headers"
  def headers, do: :headers

  @doc "Key for response body"
  def response, do: :response

  # Error Keys
  @doc "Key for error information"
  def error, do: :error

  @doc "Key for error reason"
  def reason, do: :reason

  @doc "Key for stacktrace"
  def stacktrace, do: :stacktrace

  @doc "Key for exception"
  def exception, do: :exception

  # Cache Keys
  @doc "Key for cache key"
  def key, do: :key

  @doc "Key for cache TTL"
  def ttl, do: :ttl

  @doc "Key for cache hit/miss"
  def cache_result, do: :cache_result

  # Processing Keys
  @doc "Key for entity type"
  def entity, do: :entity

  @doc "Key for entity name"
  def name, do: :name

  @doc "Key for count"
  def count, do: :count

  @doc "Key for processing status"
  def status, do: :status

  @doc "Key for processing result"
  def result, do: :result

  # Service Keys
  @doc "Key for service name"
  def service, do: :service

  @doc "Key for component name"
  def component, do: :component

  @doc "Key for feature name"
  def feature, do: :feature

  @doc "Key for scheduler name"
  def scheduler, do: :scheduler

  # Timing Keys
  @doc "Key for start time"
  def start_time, do: :start_time

  @doc "Key for end time"
  def end_time, do: :end_time

  @doc "Key for timestamp"
  def timestamp, do: :timestamp

  # Data Keys
  @doc "Key for data payload"
  def data, do: :data

  @doc "Key for query parameters"
  def query, do: :query

  @doc "Key for field name"
  def field, do: :field

  @doc "Key for value"
  def value, do: :value

  # Notification Keys
  @doc "Key for notification type"
  def notification_type, do: :notification_type

  @doc "Key for channel ID"
  def channel_id, do: :channel_id

  @doc "Key for message content"
  def message, do: :message

  # System Keys
  @doc "Key for system name"
  def system_name, do: :system_name

  @doc "Key for region name"
  def region_name, do: :region_name

  @doc "Key for map name"
  def map_name, do: :map_name
end
