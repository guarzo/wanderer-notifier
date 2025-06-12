defmodule WandererNotifier.Logger.Messages do
  @moduledoc """
  Centralized log message templates for consistent logging across the application.
  """

  # HTTP/API Message Templates
  @doc "Message for failed HTTP requests"
  def http_request_failed(method, url), do: "HTTP #{method} request failed for #{url}"

  @doc "Message for successful HTTP requests"
  def http_request_success(method, url), do: "HTTP #{method} request successful for #{url}"

  @doc "Message for API timeouts"
  def api_timeout(service, resource), do: "#{service} API timeout for #{resource}"

  @doc "Message for invalid response data"
  def invalid_response_data(service, resource),
    do: "#{service} received invalid data for #{resource}"

  @doc "Message for resource not found"
  def resource_not_found(service, resource), do: "#{service}: #{resource} not found"

  # Processing Message Templates
  @doc "Message for processing start"
  def processing_started(entity), do: "Started processing #{entity}"

  @doc "Message for processing completion"
  def processing_completed(entity), do: "Completed processing #{entity}"

  @doc "Message for processing failure"
  def processing_failed(entity, reason), do: "Failed to process #{entity}: #{reason}"

  @doc "Message for initialization"
  def initialized(component), do: "#{component} initialized"

  @doc "Message for shutdown"
  def shutdown(component), do: "#{component} shutting down"

  # Cache Message Templates
  @doc "Message for cache hits"
  def cache_hit(resource), do: "Cache hit for #{resource}"

  @doc "Message for cache misses"
  def cache_miss(resource), do: "Cache miss for #{resource}"

  @doc "Message for failed cache operations"
  def cache_operation_failed(operation, key), do: "Cache #{operation} failed for key: #{key}"

  @doc "Message for successful cache put"
  def cache_put(key, :infinity), do: "Cached #{key} with TTL infinity"
  def cache_put(key, ttl_seconds), do: "Cached #{key} with TTL #{ttl_seconds}s"

  # Killmail Message Templates
  @doc "Message for sent killmail notifications"
  def killmail_sent(id, system), do: "Killmail ##{id} | #{system} | Notification sent"

  @doc "Message for skipped killmail notifications"
  def killmail_skipped(id, system, reason), do: "Killmail ##{id} | #{system} | #{reason}"

  @doc "Message for duplicate killmails"
  def killmail_duplicate(id), do: "Duplicate killmail ##{id}"

  @doc "Message for killmail processing"
  def killmail_processing(id), do: "Processing killmail ##{id}"

  # Scheduler Message Templates
  @doc "Message for scheduler initialization"
  def scheduler_initialized(name), do: "#{name} scheduler initialized"

  @doc "Message for scheduler updates"
  def scheduler_update_started(name), do: "#{name} scheduler update started"

  @doc "Message for scheduler completion"
  def scheduler_update_completed(name, count), do: "#{name} scheduler updated #{count} items"

  @doc "Message for scheduler failures"
  def scheduler_update_failed(name, reason), do: "#{name} scheduler update failed: #{reason}"

  @doc "Message for disabled features"
  def feature_disabled(feature), do: "#{feature} is disabled"

  # Validation Message Templates
  @doc "Message for missing fields"
  def missing_field(entity, field), do: "Missing #{field} in #{entity}"

  @doc "Message for invalid data"
  def invalid_data(entity, field), do: "Invalid #{field} in #{entity}"

  @doc "Message for validation failures"
  def validation_failed(entity, reason), do: "Validation failed for #{entity}: #{reason}"

  # Service Message Templates
  @doc "Message for service start"
  def service_started(service), do: "#{service} service started"

  @doc "Message for service stop"
  def service_stopped(service), do: "#{service} service stopped"

  @doc "Message for service errors"
  def service_error(service, error), do: "#{service} service error: #{error}"

  # Connection Message Templates
  @doc "Message for connection success"
  def connected_to(service), do: "Connected to #{service}"

  @doc "Message for connection failure"
  def connection_failed(service, reason), do: "Failed to connect to #{service}: #{reason}"

  @doc "Message for disconnection"
  def disconnected_from(service), do: "Disconnected from #{service}"

  # Generic Message Templates
  @doc "Message for generic failures"
  def failed_to(action), do: "Failed to #{action}"

  @doc "Message for generic success"
  def successfully(action), do: "Successfully #{action}"

  @doc "Message for retries"
  def retrying(action, attempt), do: "Retrying #{action} (attempt #{attempt})"

  @doc "Message for generic errors"
  def error_in(component, error), do: "Error in #{component}: #{error}"
end
