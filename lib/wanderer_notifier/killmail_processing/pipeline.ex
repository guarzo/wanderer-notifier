defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Pipeline for processing killmail data from start to finish.
  Handles tasks like enrichment, validation, persistence, and notifications.

  This module serves as a facade to the unified KillmailProcessor, providing
  backward compatibility with existing code while leveraging the improved
  architecture of the new processor.
  """

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.KillmailProcessing.{Context, KillmailData, Metrics}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.KillmailProcessor

  @type killmail :: KillmailData.t() | map()
  @type result :: {:ok, any()} | {:error, any()}

  @doc """
  Process a killmail through the pipeline.

  This function delegates to the new KillmailProcessor while maintaining
  the existing interface for backward compatibility.
  """
  @spec process_killmail(map(), Context.t()) :: result()
  def process_killmail(zkb_data, ctx) do
    Metrics.track_processing_start(ctx)
    Stats.increment(:kill_processed)

    # Delegate to the new KillmailProcessor
    result = KillmailProcessor.process_killmail(zkb_data, ctx)

    # Handle result and metrics
    case result do
      {:ok, processed_killmail} ->
        # Successfully processed killmail
        Metrics.track_processing_complete(ctx, {:ok, processed_killmail})

        # Check if the killmail was persisted
        persisted =
          if is_map(processed_killmail),
            do: Map.get(processed_killmail, :persisted, true),
            else: true

        # Log outcome (simplified for now)
        log_killmail_outcome(processed_killmail, ctx, persisted: persisted)

        # Return success
        {:ok, processed_killmail}

      {:ok, :skipped} ->
        # Killmail was explicitly skipped
        Metrics.track_processing_skipped(ctx)
        log_killmail_outcome(zkb_data, ctx, persisted: false, reason: "Skipped by processor")
        {:ok, :skipped}

      {:error, reason} ->
        # Error in processing
        Metrics.track_processing_error(ctx)

        # Extract killmail ID for logging
        kill_id = extract_kill_id(zkb_data)

        # Log error
        AppLogger.kill_debug("Error processing killmail ##{kill_id}", %{
          error: inspect(reason),
          kill_id: kill_id,
          status: "failed"
        })

        # Return the error for proper handling
        {:error, reason}
    end
  end

  @doc """
  Process a pre-created KillmailData struct through the pipeline.

  This function delegates to the new KillmailProcessor while maintaining
  the existing interface for backward compatibility.
  """
  @spec process_killmail_with_data(KillmailData.t(), Context.t()) :: result()
  def process_killmail_with_data(%KillmailData{} = killmail, ctx) do
    Metrics.track_processing_start(ctx)

    AppLogger.kill_debug("Processing pre-created killmail data", %{
      kill_id: killmail.killmail_id,
      source: ctx.source,
      mode: (ctx.mode && ctx.mode.mode) || :unknown
    })

    # Check if debug force notification is enabled
    should_force_notify = ctx.metadata && Map.get(ctx.metadata, :force_notification, false)

    # Create a modified context with force_notification flag if needed
    modified_ctx =
      if should_force_notify do
        Map.put(ctx, :force_notification, true)
      else
        ctx
      end

    # Delegate to the new KillmailProcessor
    result = KillmailProcessor.process_killmail(killmail, modified_ctx)

    # Handle result and metrics
    case result do
      {:ok, processed_killmail} ->
        # Successfully processed killmail
        Metrics.track_processing_complete(ctx, {:ok, processed_killmail})

        # Check if the killmail was persisted
        persisted =
          if is_map(processed_killmail),
            do: Map.get(processed_killmail, :persisted, true),
            else: true

        # Log outcome with override info if applicable
        override_info = if should_force_notify, do: " (notification forced)", else: ""

        log_killmail_outcome(processed_killmail, ctx,
          persisted: persisted,
          reason: "Processed#{override_info}"
        )

        # Return success
        {:ok, processed_killmail}

      {:ok, :skipped} ->
        # Killmail was explicitly skipped
        Metrics.track_processing_skipped(ctx)
        log_killmail_outcome(killmail, ctx, persisted: false, reason: "Skipped by processor")
        {:ok, :skipped}

      {:error, reason} ->
        # Error in processing
        Metrics.track_processing_error(ctx)

        # Extract killmail ID and additional information for better error logging
        kill_id = killmail.killmail_id

        # Extract system and victim information for helpful error context
        system_name = killmail.solar_system_name || "Unknown System"
        victim_name = killmail.victim_name || "Unknown Pilot"
        victim_ship = killmail.victim_ship_name || "Unknown Ship"

        AppLogger.kill_debug(
          "❌ Error processing killmail ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name}",
          %{
            kill_id: kill_id,
            system_name: system_name,
            victim_name: victim_name,
            victim_ship: victim_ship,
            error: inspect(reason)
          }
        )

        # Return the error for proper handling
        {:error, reason}
    end
  end

  # Helper to extract kill_id from various formats for error logging
  defp extract_kill_id(zkb_data) do
    cond do
      is_struct(zkb_data, KillmailData) ->
        zkb_data.killmail_id

      is_map(zkb_data) && Map.has_key?(zkb_data, :killmail_id) ->
        zkb_data.killmail_id

      is_map(zkb_data) && Map.has_key?(zkb_data, "killmail_id") ->
        zkb_data["killmail_id"]

      true ->
        "unknown"
    end
  end

  # Simplified logging helper for killmail outcomes
  defp log_killmail_outcome(killmail, _ctx, opts) do
    persisted = Keyword.get(opts, :persisted, true)
    notified = Keyword.get(opts, :notified, false)
    reason = Keyword.get(opts, :reason, "")

    # Extract killmail information
    kill_id = extract_kill_id(killmail)
    {system_name, victim_name, victim_ship} = extract_killmail_display_info(killmail)

    # Format status emoji
    status_emoji = if persisted, do: "✅", else: "❌"

    # Log a simple message
    AppLogger.kill_info("""
    #{status_emoji} Kill ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name} |
    #{if persisted, do: "Saved", else: "Not saved"}, #{if notified, do: "Notified", else: "Not notified"} - #{reason}
    """)
  end

  # Extract system and victim information based on data type
  defp extract_killmail_display_info(killmail) do
    cond do
      is_struct(killmail, KillmailData) ->
        {
          killmail.solar_system_name || "Unknown System",
          killmail.victim_name || "Unknown Pilot",
          killmail.victim_ship_name || "Unknown Ship"
        }

      is_map(killmail) ->
        system_name =
          Map.get(killmail, :solar_system_name) || Map.get(killmail, "solar_system_name") ||
            "Unknown System"

        victim_name =
          Map.get(killmail, :victim_name) || Map.get(killmail, "victim_name") || "Unknown Pilot"

        victim_ship =
          Map.get(killmail, :victim_ship_name) || Map.get(killmail, "victim_ship_name") ||
            "Unknown Ship"

        {system_name, victim_name, victim_ship}

      true ->
        {"Unknown System", "Unknown Pilot", "Unknown Ship"}
    end
  end
end
