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
      :rally_point -> notify_rally_point(state, notification)
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
          error_message = Exception.message(error)
          error_type = error.__struct__
          notification_keys = Map.keys(notification)

          Logger.error(
            "Exception in kill notification processing: #{error_type} - #{error_message}"
          )

          Logger.error("Notification keys: #{inspect(notification_keys)}")
          Logger.error("Notification sample: #{inspect(notification, limit: 500)}")
          Logger.error("Stacktrace: #{inspect(__STACKTRACE__, limit: :infinity)}")

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
          error_message = Exception.message(error)
          error_type = error.__struct__
          notification_keys = Map.keys(notification)

          Logger.error(
            "Exception in system notification processing: #{error_type} - #{error_message}"
          )

          Logger.error("Notification keys: #{inspect(notification_keys)}")
          Logger.error("Notification sample: #{inspect(notification, limit: 500)}")
          Logger.error("Stacktrace: #{inspect(__STACKTRACE__, limit: :infinity)}")

          {:error, {:exception, error}, state}
      end
    else
      Logger.debug("System notifications disabled, skipping", category: :notification)
      {:ok, :skipped, state}
    end
  end

  @doc """
  Sends a rally point notification.
  """
  @spec notify_rally_point(State.t(), map()) ::
          {:ok, atom(), State.t()} | {:error, term(), State.t()}
  def notify_rally_point(state, notification) do
    if rally_notifications_enabled?() do
      try do
        # Extract rally point data from notification
        rally_point = Map.get(notification, :rally_point)

        case WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier.send_rally_point_notification(
               rally_point
             ) do
          {:ok, :sent} ->
            {:ok, new_state} = increment_notification_count(state, :rally_points)
            Logger.debug("Rally point notification sent successfully", category: :notification)
            {:ok, :sent, new_state}

          {:error, reason} ->
            Logger.warning("Failed to send rally point notification to Discord",
              category: :notification,
              error: inspect(reason)
            )

            {:error, {:discord_send_failed, reason}, state}
        end
      rescue
        error ->
          Logger.error("Exception in rally point notification processing",
            category: :notification,
            error: Exception.message(error),
            stacktrace: __STACKTRACE__
          )

          {:error, {:exception, error}, state}
      end
    else
      Logger.debug("Rally point notifications disabled, skipping", category: :notification)
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
      killmail_notification?(notification) -> :kill
      rally_point_notification?(notification) -> :rally_point
      system_notification?(notification) -> :system
      character_notification?(notification) -> :character
      true -> :unknown
    end
  end

  defp killmail_notification?(notification) do
    Map.has_key?(notification, "killmail_id") or Map.has_key?(notification, :killmail_id)
  end

  defp rally_point_notification?(notification) do
    Map.get(notification, :type) == :rally_point or
      Map.get(notification, "type") == "rally_point"
  end

  defp system_notification?(notification) do
    Map.has_key?(notification, "solar_system_id") or
      Map.has_key?(notification, :solar_system_id)
  end

  defp character_notification?(notification) do
    Map.has_key?(notification, "character_id") or Map.has_key?(notification, :character_id)
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

  defp rally_notifications_enabled? do
    WandererNotifier.Shared.Config.get(:rally_notifications_enabled, true)
  end

  defp priority_systems_only? do
    WandererNotifier.Shared.Config.get(:priority_systems_only, false)
  end

  defp in_priority_system?(notification) do
    system_id = extract_system_id_from_notification(notification)

    case system_id do
      nil -> true
      id -> check_if_priority_system(id)
    end
  end

  defp extract_system_id_from_notification(notification) do
    # Try direct access patterns
    direct_patterns = [
      [:system_id],
      ["system_id"]
    ]

    # Try nested killmail patterns
    killmail_patterns = [
      [:killmail, :system_id],
      [:killmail, "system_id"],
      ["killmail", "system_id"],
      [:killmail, :solar_system_id],
      [:killmail, "solar_system_id"],
      ["killmail", "solar_system_id"]
    ]

    # Check all patterns
    all_patterns = direct_patterns ++ killmail_patterns

    Enum.find_value(all_patterns, fn pattern ->
      get_in(notification, pattern)
    end)
  end

  defp check_if_priority_system(system_id) do
    priority_systems = WandererNotifier.Shared.Config.get(:priority_systems, [])
    system_id_str = to_string(system_id)
    Enum.member?(priority_systems, system_id_str)
  end
end
