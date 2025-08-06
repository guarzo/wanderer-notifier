defmodule WandererNotifier.Domains.Notifications.Errors do
  @moduledoc """
  Domain-specific error types for the Notifications domain.

  Provides consistent error handling and formatting for notification processing,
  Discord integration, and message formatting operations.
  """

  @doc """
  Creates a notification processing error.

  ## Examples
      
      iex> notification_error(:invalid_format)
      {:error, {:notification, :invalid_format}}
      
      iex> notification_error(:send_failed, "Rate limited")
      {:error, {:notification, {:send_failed, "Rate limited"}}}
  """
  def notification_error(reason) when is_atom(reason) do
    {:error, {:notification, reason}}
  end

  def notification_error(reason, context) do
    {:error, {:notification, {reason, context}}}
  end

  @doc """
  Creates a Discord integration error.
  """
  def discord_error(reason) when is_atom(reason) do
    {:error, {:discord, reason}}
  end

  def discord_error(reason, context) do
    {:error, {:discord, {reason, context}}}
  end

  @doc """
  Creates a formatting error.
  """
  def format_error_type(reason) when is_atom(reason) do
    {:error, {:format, reason}}
  end

  def format_error_type(reason, context) do
    {:error, {:format, {reason, context}}}
  end

  @doc """
  Creates a delivery error.
  """
  def delivery_error(reason) when is_atom(reason) do
    {:error, {:delivery, reason}}
  end

  def delivery_error(reason, context) do
    {:error, {:delivery, {reason, context}}}
  end

  @doc """
  Formats notification domain errors into user-friendly messages.

  ## Examples

      iex> format_error({:notification, :invalid_format})
      "Invalid notification format"
      
      iex> format_error({:discord, :rate_limited})
      "Discord API rate limited"
  """
  def format_error({:notification, :invalid_format}), do: "Invalid notification format"
  def format_error({:notification, :missing_data}), do: "Missing notification data"
  def format_error({:notification, :type_unknown}), do: "Unknown notification type"
  def format_error({:notification, :disabled}), do: "Notifications are disabled"
  def format_error({:notification, :duplicate}), do: "Duplicate notification detected"
  def format_error({:notification, reason}), do: "Notification error: #{inspect(reason)}"

  def format_error({:discord, :authentication_failed}), do: "Discord authentication failed"
  def format_error({:discord, :rate_limited}), do: "Discord API rate limited"
  def format_error({:discord, :channel_not_found}), do: "Discord channel not found"
  def format_error({:discord, :permission_denied}), do: "Discord permission denied"
  def format_error({:discord, :api_unavailable}), do: "Discord API unavailable"
  def format_error({:discord, :invalid_token}), do: "Invalid Discord bot token"
  def format_error({:discord, :webhook_failed}), do: "Discord webhook delivery failed"
  def format_error({:discord, reason}), do: "Discord error: #{inspect(reason)}"

  def format_error({:format, :invalid_template}), do: "Invalid notification template"
  def format_error({:format, :missing_field}), do: "Missing required field for formatting"
  def format_error({:format, :encoding_error}), do: "Message encoding error"
  def format_error({:format, :size_exceeded}), do: "Message size limit exceeded"
  def format_error({:format, reason}), do: "Formatting error: #{inspect(reason)}"

  def format_error({:delivery, :timeout}), do: "Notification delivery timed out"
  def format_error({:delivery, :network_error}), do: "Network error during delivery"
  def format_error({:delivery, :service_unavailable}), do: "Delivery service unavailable"
  def format_error({:delivery, :quota_exceeded}), do: "Delivery quota exceeded"
  def format_error({:delivery, reason}), do: "Delivery error: #{inspect(reason)}"

  def format_error(reason), do: "Unknown notification domain error: #{inspect(reason)}"

  @doc """
  Checks if an error is from the notifications domain.
  """
  def notification_error?({:error, {:notification, _}}), do: true
  def notification_error?({:error, {:discord, _}}), do: true
  def notification_error?({:error, {:format, _}}), do: true
  def notification_error?({:error, {:delivery, _}}), do: true
  def notification_error?(_), do: false

  @doc """
  Extracts the error reason from a notifications domain error.
  """
  def extract_reason({:error, {:notification, reason}}), do: reason
  def extract_reason({:error, {:discord, reason}}), do: reason
  def extract_reason({:error, {:format, reason}}), do: reason
  def extract_reason({:error, {:delivery, reason}}), do: reason
  def extract_reason({:error, reason}), do: reason

  @doc """
  Categorizes notification errors for logging and monitoring.
  """
  def categorize_error({:notification, _}), do: :notification_processing
  def categorize_error({:discord, _}), do: :discord_integration
  def categorize_error({:format, _}), do: :message_formatting
  def categorize_error({:delivery, _}), do: :message_delivery
  def categorize_error(_), do: :unknown_notification

  @doc """
  Determines if a notification error is retryable.
  """
  def retryable_error?({:discord, :rate_limited}), do: true
  def retryable_error?({:discord, :api_unavailable}), do: true
  def retryable_error?({:delivery, :timeout}), do: true
  def retryable_error?({:delivery, :network_error}), do: true
  def retryable_error?({:delivery, :service_unavailable}), do: true
  def retryable_error?({:notification, :disabled}), do: false
  def retryable_error?({:discord, :authentication_failed}), do: false
  def retryable_error?({:discord, :permission_denied}), do: false
  def retryable_error?(_), do: false
end
