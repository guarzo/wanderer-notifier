defmodule WandererNotifier.Application.Services.ApplicationService.NotificationCoordinator do
  @moduledoc """
  Coordinates notification processing for the ApplicationService.

  Consolidates notification logic from the original NotificationService and
  provides a clean interface for processing different types of notifications.
  """

  require Logger
  alias WandererNotifier.Application.Services.ApplicationService.State
  alias WandererNotifier.Shared.Types.CommonTypes

  @type notification_result :: CommonTypes.result(term())

  @doc """
  Initializes the notification coordinator.
  """
  @spec initialize(State.t()) :: {:ok, State.t()}
  def initialize(state) do
    Logger.debug("Initializing notification coordinator...", category: :startup)
    {:ok, state}
  end

  @doc """
  Processes a notification through the appropriate channels.
  """
  @spec process_notification(State.t(), map(), keyword()) ::
          {:ok, term(), State.t()} | {:error, term(), State.t()}
  def process_notification(state, notification, opts \\ []) do
    # Determine notification type and route accordingly
    case determine_notification_type(notification) do
      :kill -> notify_kill(state, notification)
      :system -> notify_system(state, notification, opts)
      :character -> notify_character(state, notification, opts)
      :unknown -> {:error, {:unknown_notification_type, notification}, state}
    end
  end

  @doc """
  Sends a kill notification.
  """
  @spec notify_kill(State.t(), map()) :: {:ok, atom(), State.t()} | {:error, term(), State.t()}
  def notify_kill(state, notification) do
    # Check if notifications are enabled
    cond do
      not notifications_enabled?() ->
        Logger.debug("Notifications disabled, skipping kill notification",
          category: :notification
        )

        {:ok, :skipped, state}

      not kill_notifications_enabled?() ->
        Logger.debug("Kill notifications disabled, skipping", category: :notification)
        {:ok, :skipped, state}

      true ->
        process_kill_notification(state, notification)
    end
  end

  defp process_kill_notification(state, notification) do
    # Check priority system requirements
    if priority_systems_only?() and not in_priority_system?(notification) do
      Logger.debug("Kill not in priority system, skipping", category: :notification)
      {:ok, :skipped, state}
    else
      try do
        # Use the unified notification formatter and Discord notifier
        formatted =
          WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter.format_notification(
            notification
          )

        case send_to_discord(formatted) do
          :ok ->
            # Update metrics
            {:ok, new_state} = increment_notification_count(state, :kills)
            Logger.debug("Kill notification sent successfully", category: :notification)
            {:ok, :sent, new_state}

          {:error, reason} ->
            Logger.warning("Failed to send kill notification to Discord",
              category: :notification,
              error: inspect(reason)
            )

            {:error, {:discord_send_failed, reason}, state}
        end
      rescue
        error ->
          Logger.error("Exception in kill notification processing",
            category: :notification,
            error: Exception.message(error),
            stacktrace: __STACKTRACE__
          )

          {:error, {:exception, error}, state}
      end
    end
  end

  @doc """
  Sends a system notification.
  """
  @spec notify_system(State.t(), map(), keyword()) ::
          {:ok, atom(), State.t()} | {:error, term(), State.t()}
  def notify_system(state, notification, opts \\ []) do
    if system_notifications_enabled?() do
      try do
        formatted =
          WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter.format_notification(
            notification
          )

        case send_to_discord(formatted, opts) do
          :ok ->
            {:ok, new_state} = increment_notification_count(state, :systems)
            Logger.debug("System notification sent successfully", category: :notification)
            {:ok, :sent, new_state}

          {:error, reason} ->
            Logger.warning("Failed to send system notification to Discord",
              category: :notification,
              error: inspect(reason)
            )

            {:error, {:discord_send_failed, reason}, state}
        end
      rescue
        error ->
          Logger.error("Exception in system notification processing",
            category: :notification,
            error: Exception.message(error),
            stacktrace: __STACKTRACE__
          )

          {:error, {:exception, error}, state}
      end
    else
      Logger.debug("System notifications disabled, skipping", category: :notification)
      {:ok, :skipped, state}
    end
  end

  @doc """
  Sends a character notification.
  """
  @spec notify_character(State.t(), map(), keyword()) ::
          {:ok, atom(), State.t()} | {:error, term(), State.t()}
  def notify_character(state, notification, opts \\ []) do
    if character_notifications_enabled?() do
      try do
        formatted =
          WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter.format_notification(
            notification
          )

        case send_to_discord(formatted, opts) do
          :ok ->
            {:ok, new_state} = increment_notification_count(state, :characters)
            Logger.debug("Character notification sent successfully", category: :notification)
            {:ok, :sent, new_state}

          {:error, reason} ->
            Logger.warning("Failed to send character notification to Discord",
              category: :notification,
              error: inspect(reason)
            )

            {:error, {:discord_send_failed, reason}, state}
        end
      rescue
        error ->
          Logger.error("Exception in character notification processing",
            category: :notification,
            error: Exception.message(error),
            stacktrace: __STACKTRACE__
          )

          {:error, {:exception, error}, state}
      end
    else
      Logger.debug("Character notifications disabled, skipping", category: :notification)
      {:ok, :skipped, state}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp determine_notification_type(notification) do
    cond do
      Map.has_key?(notification, "killmail_id") or Map.has_key?(notification, :killmail_id) ->
        :kill

      Map.has_key?(notification, "solar_system_id") or
          Map.has_key?(notification, :solar_system_id) ->
        :system

      Map.has_key?(notification, "character_id") or Map.has_key?(notification, :character_id) ->
        :character

      true ->
        :unknown
    end
  end

  defp increment_notification_count(state, type) do
    State.update_metrics(state, fn metrics ->
      notifications = Map.update(metrics.notifications, type, 1, &(&1 + 1))
      notifications = Map.update(notifications, :total, 1, &(&1 + 1))
      %{metrics | notifications: notifications}
    end)
    |> then(&{:ok, &1})
  end

  defp send_to_discord(formatted_notification, opts \\ []) do
    channel_id = Keyword.get(opts, :channel_id, get_default_channel_id())

    WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient.send_embed(
      formatted_notification,
      channel_id
    )
  end

  defp get_default_channel_id do
    WandererNotifier.Shared.Config.discord_channel_id()
  end

  # Feature flags
  defp notifications_enabled? do
    WandererNotifier.Shared.Config.get(:notifications_enabled, true)
  end

  defp kill_notifications_enabled? do
    WandererNotifier.Shared.Config.get(:kill_notifications_enabled, true)
  end

  defp system_notifications_enabled? do
    WandererNotifier.Shared.Config.get(:system_notifications_enabled, true)
  end

  defp character_notifications_enabled? do
    WandererNotifier.Shared.Config.get(:character_notifications_enabled, true)
  end

  defp priority_systems_only? do
    WandererNotifier.Shared.Config.get(:priority_systems_only, false)
  end

  defp in_priority_system?(_notification) do
    # This would check if the killmail occurred in a priority system
    # Implementation would depend on how priority systems are defined
    # For now, assume all systems are priority
    true
  end
end
