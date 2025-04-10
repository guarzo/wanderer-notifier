defmodule WandererNotifier.Debug.PipelineDebug do
  @moduledoc """
  Debug module for the killmail processing pipeline.

  This module directly uses the real production pipeline code but provides
  convenient ways to test specific kills.
  """

  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.KillmailProcessing.{Context, Pipeline}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Hardcoded debug character ID
  @debug_character_id 640_170_087
  @debug_character_name "Debug Character"

  @doc """
  Analyze a specific killmail by running it through the real pipeline.

  ## Parameters
  - killmail_id: The ID of the killmail to analyze
  - character_index: The index of character to use (0 for debug character)
  """
  def analyze_pipeline(killmail_id, character_index \\ 0) do
    # Get character info
    character_id =
      if character_index == 0, do: @debug_character_id, else: get_character_id(character_index)

    character_name =
      if character_index == 0,
        do: @debug_character_name,
        else: get_character_name(character_index)

    AppLogger.kill_debug("""
    ⚡ USING REAL PIPELINE: Running killmail directly through the production pipeline
    * Kill ID: #{killmail_id}
    * Character ID: #{character_id}
    * Character name: #{character_name}
    """)

    # Create processing context
    ctx =
      Context.new_historical(
        character_id,
        character_name,
        :debug,
        "debug-#{:os.system_time(:millisecond)}",
        skip_notification: false,
        force_notification: true
      )

    # Fetch the specific kill from ZKill
    case ZKillClient.get_single_killmail(killmail_id) do
      {:ok, kill} ->
        AppLogger.kill_debug("""
        🔄 Passing raw ZKill data directly to the REAL Pipeline.process_killmail function
        * Kill ID: #{killmail_id}
        * Using production code path with no special handling
        """)

        # Run the kill through the real pipeline
        t0 = System.monotonic_time(:millisecond)
        result = Pipeline.process_killmail(kill, ctx)
        t1 = System.monotonic_time(:millisecond)
        duration_ms = t1 - t0

        case result do
          {:ok, processed_data} ->
            # Check if the kill was persisted based on the returned data
            persisted_status =
              cond do
                is_map(processed_data) && Map.has_key?(processed_data, :persisted) ->
                  if processed_data.persisted do
                    "✅ Persisted to database"
                  else
                    reason = extract_not_persisted_reason(processed_data)
                    "❌ Not persisted to database (#{reason || "unknown reason"})"
                  end

                true ->
                  "Unknown persistence status"
              end

            # Try to extract notification status
            notification_status = extract_notification_status(processed_data)

            # Extract some key fields for display
            ship_name = extract_ship_name(processed_data)
            system_name = extract_system_name(processed_data)
            victim_name = extract_victim_name(processed_data)

            AppLogger.kill_debug("""
            ✅ PIPELINE SUCCESS! Killmail processed successfully through the REAL pipeline!
            * Killmail ID: #{killmail_id}
            * Duration: #{duration_ms}ms
            * System: #{system_name || "unknown"}
            * Victim: #{victim_name || "unknown"} in #{ship_name || "unknown ship"}

            RESULTS:
            * Database: #{persisted_status}
            * Notification: #{notification_status}

            The return value is a fully processed KillmailData struct containing all kill details.
            This is the expected successful result and NOT an error!
            """)

            result

          error ->
            AppLogger.kill_error("""
            ❌ PIPELINE ERROR! Killmail processing failed in the real pipeline:
            * Killmail ID: #{killmail_id}
            * Duration: #{duration_ms}ms
            * Error: #{inspect(error)}
            """)

            error
        end

      {:error, reason} ->
        AppLogger.kill_error("""
        ❌ FETCH ERROR: Failed to fetch kill from ZKill
        * Kill ID: #{killmail_id}
        * Error: #{inspect(reason)}
        """)

        {:error, reason}
    end
  end

  # Helper to get character ID from index
  defp get_character_id(index) do
    tracked_characters = WandererNotifier.Data.Repository.get_tracked_characters()

    if length(tracked_characters) >= index do
      character = Enum.at(tracked_characters, index - 1)

      # Get character_id field
      cond do
        is_map(character) && Map.has_key?(character, :character_id) -> character.character_id
        is_map(character) && Map.has_key?(character, "character_id") -> character["character_id"]
        true -> @debug_character_id
      end
    else
      @debug_character_id
    end
  end

  # Helper to get character name from index
  defp get_character_name(index) do
    tracked_characters = WandererNotifier.Data.Repository.get_tracked_characters()

    if length(tracked_characters) >= index do
      character = Enum.at(tracked_characters, index - 1)

      # Get character_name field
      cond do
        is_map(character) && Map.has_key?(character, :character_name) ->
          character.character_name

        is_map(character) && Map.has_key?(character, "character_name") ->
          character["character_name"]

        true ->
          "Unknown Character"
      end
    else
      @debug_character_name
    end
  end

  # Helper functions to extract information from the processed data

  defp extract_not_persisted_reason(processed_data) do
    metadata = Map.get(processed_data, :metadata, %{})

    cond do
      Map.has_key?(metadata, :persistence_reason) ->
        metadata.persistence_reason

      Map.has_key?(metadata, :not_persisted_reason) ->
        metadata.not_persisted_reason

      true ->
        "Kill might not be tracked by any character"
    end
  end

  defp extract_notification_status(processed_data) do
    metadata = Map.get(processed_data, :metadata, %{})

    cond do
      Map.has_key?(metadata, :notification_sent) && metadata.notification_sent ->
        "✅ Notification sent"

      Map.has_key?(metadata, :notification_reason) ->
        "❌ No notification sent (#{metadata.notification_reason})"

      # Try reading from the Process dictionary if Pipeline stored info there
      Process.get(:last_notification_reason) ->
        if Process.get(:last_notification_sent, false) do
          "✅ Notification sent (from Process data)"
        else
          "❌ No notification sent (#{Process.get(:last_notification_reason)})"
        end

      true ->
        "Unknown notification status"
    end
  end

  defp extract_ship_name(processed_data) do
    # Try several paths to get the victim ship name
    cond do
      is_map(processed_data) && Map.has_key?(processed_data, :victim_ship_name) ->
        processed_data.victim_ship_name

      is_map(processed_data) && Map.has_key?(processed_data, :victim) &&
        is_map(processed_data.victim) && Map.has_key?(processed_data.victim, "ship_type_name") ->
        processed_data.victim["ship_type_name"]

      true ->
        nil
    end
  end

  defp extract_system_name(processed_data) do
    # Try to get the solar system name
    cond do
      is_map(processed_data) && Map.has_key?(processed_data, :solar_system_name) ->
        processed_data.solar_system_name

      is_map(processed_data) && Map.has_key?(processed_data, :esi_data) &&
        is_map(processed_data.esi_data) &&
          Map.has_key?(processed_data.esi_data, "solar_system_name") ->
        processed_data.esi_data["solar_system_name"]

      true ->
        nil
    end
  end

  defp extract_victim_name(processed_data) do
    # Try to get the victim name
    cond do
      is_map(processed_data) && Map.has_key?(processed_data, :victim_name) ->
        processed_data.victim_name

      is_map(processed_data) && Map.has_key?(processed_data, :victim) &&
        is_map(processed_data.victim) && Map.has_key?(processed_data.victim, "character_name") ->
        processed_data.victim["character_name"]

      true ->
        nil
    end
  end
end
