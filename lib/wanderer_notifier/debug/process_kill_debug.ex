defmodule WandererNotifier.Debug.ProcessKillDebug do
  @moduledoc """
  Debug module for testing kill processing for a single character.
  This helps isolate issues with the kill processing pipeline.

  IMPORTANT: This module uses the REAL production pipeline code, not a special debug version.
  It provides additional logging and easier entry points, but the actual processing code
  is identical to what's used in production.
  """

  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Data.Repository
  alias WandererNotifier.KillmailProcessing.{Context, Pipeline}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Hardcoded character ID that's known to have killmails
  # This can be used with index 0 in the debug functions
  @debug_character_id 1_406_208_348
  @debug_character_name "Debug Character"

  @doc """
  Process a single kill for a character.
  Uses character index (1-based) to select from tracked characters.
  Use index 0 for the hardcoded debug character with guaranteed kills.

  ## Options
    * `:kill_limit` - Limit the number of kills to process (default: 1)
    * `:force_debug_character` - Force using the debug character regardless of index
  """
  def process_single_kill(character_index, opts \\ []) when is_integer(character_index) do
    # Get options with defaults
    kill_limit = Keyword.get(opts, :kill_limit, 1)
    force_debug = Keyword.get(opts, :force_debug_character, false)

    # Use either debug character or fetch from database
    if character_index == 0 || force_debug do
      process_debug_character_kill(kill_limit)
    else
      process_regular_character_kill(character_index, kill_limit)
    end
  end

  defp process_debug_character_kill(kill_limit) do
    AppLogger.kill_debug("Using hardcoded debug character", %{
      character_id: @debug_character_id,
      character_name: @debug_character_name,
      kill_limit: kill_limit
    })

    # Use the hardcoded debug character ID
    character_id = @debug_character_id
    character_name = @debug_character_name

    # Create debug context with integer character_id
    ctx =
      Context.new_historical(
        character_id,
        character_name,
        :debug,
        "debug-#{:os.system_time(:millisecond)}",
        skip_notification: false,
        force_notification: true
      )

    process_character_kills(character_id, character_name, ctx, kill_limit)
  end

  defp process_regular_character_kill(character_index, kill_limit) do
    # Get all tracked characters
    tracked_characters = Repository.get_tracked_characters()

    if length(tracked_characters) >= character_index do
      # Get character by index (adjust for 1-based indexing)
      character = Enum.at(tracked_characters, character_index - 1)

      # Extract character ID and name
      character_id =
        cond do
          is_map(character) && Map.has_key?(character, :character_id) ->
            # Convert to integer if it's a string
            case character.character_id do
              id when is_integer(id) ->
                id

              id when is_binary(id) ->
                case Integer.parse(id) do
                  {int_id, _} -> int_id
                  _ -> id
                end

              id ->
                id
            end

          is_map(character) && Map.has_key?(character, "character_id") ->
            # Convert to integer if it's a string
            case character["character_id"] do
              id when is_integer(id) ->
                id

              id when is_binary(id) ->
                case Integer.parse(id) do
                  {int_id, _} -> int_id
                  _ -> id
                end

              id ->
                id
            end

          true ->
            nil
        end

      character_name =
        cond do
          is_map(character) && Map.has_key?(character, :character_name) ->
            character.character_name

          is_map(character) && Map.has_key?(character, "character_name") ->
            character["character_name"]

          true ->
            "Unknown Character"
        end

      # Log character information for debugging
      AppLogger.kill_debug("Processing character", %{
        index: character_index,
        character_id: character_id,
        character_name: character_name,
        character_id_type: typeof(character_id)
      })

      if is_nil(character_id) do
        AppLogger.kill_error("Invalid character ID - cannot process kills", %{
          character: inspect(character, limit: 200)
        })

        {:error, :invalid_character_id}
      else
        # Create context with the extracted character information
        ctx =
          Context.new_historical(
            character_id,
            character_name,
            :debug,
            "debug-#{:os.system_time(:millisecond)}",
            skip_notification: false,
            force_notification: true
          )

        # Process kills for this character
        process_character_kills(character_id, character_name, ctx, kill_limit)
      end
    else
      AppLogger.kill_error("Character index out of bounds", %{
        index: character_index,
        tracked_count: length(tracked_characters)
      })

      {:error, :character_not_found}
    end
  end

  # Helper function to process kills for a character with proper error handling
  defp process_character_kills(character_id, character_name, _ctx, kill_limit) do
    try do
      # Ensure character_id is an integer
      character_id_int = ensure_integer_id(character_id)

      AppLogger.kill_debug("Fetching kills for character", %{
        character_id: character_id_int,
        character_name: character_name,
        kill_limit: kill_limit
      })

      # Fetch kills from ZKill
      case ZKillClient.get_character_kills(character_id_int, %{start: nil, end: nil}, kill_limit) do
        {:ok, kills} when is_list(kills) and length(kills) > 0 ->
          # Get the first kill for processing
          raw_kill = List.first(kills)
          kill_id = Map.get(raw_kill, "killmail_id")

          AppLogger.kill_debug("Processing kill using standard pipeline", %{
            kill_id: kill_id,
            character_id: character_id_int,
            character_name: character_name
          })

          # Use the standard debug_kill_notification path for consistent processing
          result = debug_kill_notification(kill_id)

          AppLogger.kill_debug("Kill processing completed via standard pipeline", %{
            kill_id: kill_id,
            success: match?(%{success: true}, result)
          })

          # Return the simplified result from debug_kill_notification
          {:ok, result}

        {:ok, []} ->
          AppLogger.kill_warn("No kills found for character", %{
            character_id: character_id_int,
            character_name: character_name
          })

          {:error, :no_kills_found}

        {:error, reason} ->
          AppLogger.kill_error("Failed to fetch kills", %{
            character_id: character_id_int,
            character_name: character_name,
            error: inspect(reason)
          })

          {:error, reason}
      end
    rescue
      e ->
        stacktrace = __STACKTRACE__

        AppLogger.kill_error("Exception processing character kills", %{
          character_id: character_id,
          character_name: character_name,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(stacktrace)
        })

        {:error, {:exception, Exception.message(e)}}
    end
  end

  # Helper to ensure character_id is an integer
  defp ensure_integer_id(id) when is_integer(id), do: id

  defp ensure_integer_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} ->
        int_id

      _ ->
        AppLogger.kill_warn("[DEBUG] Invalid character ID format", %{
          character_id: id
        })

        # Return the original id to let the downstream functions handle the error
        id
    end
  end

  defp ensure_integer_id(id), do: id

  # Helper to get type of a value for better debugging
  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_atom(value), do: "atom"
  defp typeof(value) when is_nil(value), do: "nil"
  defp typeof(_value), do: "unknown"

  @doc """
  Process a specific kill ID for a character.
  Uses character index (1-based) to select from tracked characters.
  Use index 0 for the hardcoded debug character.
  """
  def process_specific_kill(character_index, kill_id) when is_integer(character_index) do
    # Get all tracked characters
    tracked_characters = Repository.get_tracked_characters()

    character_info =
      if character_index == 0 do
        # Use the hardcoded debug character
        %{
          character_id: @debug_character_id,
          character_name: @debug_character_name
        }
      else
        if length(tracked_characters) >= character_index do
          # Get character by index (adjust for 1-based indexing)
          character = Enum.at(tracked_characters, character_index - 1)

          # Extract character information
          %{
            character_id: get_character_id(character),
            character_name: get_character_name(character)
          }
        else
          AppLogger.kill_error("Character index out of bounds", %{
            index: character_index,
            tracked_count: length(tracked_characters)
          })

          nil
        end
      end

    if character_info do
      # Use the debug_kill_notification flow to ensure it's the same pipeline
      character_id = character_info.character_id
      character_name = character_info.character_name

      AppLogger.kill_debug("Processing specific kill with standard pipeline", %{
        kill_id: kill_id,
        character_id: character_id,
        character_name: character_name
      })

      debug_kill_notification(kill_id)
    else
      {:error, :invalid_character_index}
    end
  end

  # Helper to extract character ID safely
  defp get_character_id(character) do
    cond do
      is_map(character) && Map.has_key?(character, :character_id) ->
        # Convert to integer if it's a string
        case character.character_id do
          id when is_integer(id) ->
            id

          id when is_binary(id) ->
            case Integer.parse(id) do
              {int_id, _} -> int_id
              _ -> id
            end

          id ->
            id
        end

      is_map(character) && Map.has_key?(character, "character_id") ->
        # Convert to integer if it's a string
        case character["character_id"] do
          id when is_integer(id) ->
            id

          id when is_binary(id) ->
            case Integer.parse(id) do
              {int_id, _} -> int_id
              _ -> id
            end

          id ->
            id
        end

      true ->
        nil
    end
  end

  # Helper to extract character name safely
  defp get_character_name(character) do
    cond do
      is_map(character) && Map.has_key?(character, :character_name) ->
        character.character_name

      is_map(character) && Map.has_key?(character, "character_name") ->
        character["character_name"]

      true ->
        "Unknown Character"
    end
  end

  @doc """
  Debug function to process all kills for a character.
  Uses character index (1-based) to select from tracked characters.
  Use index 0 for the hardcoded debug character.

  ## Options
    * `:kill_limit` - Limit the number of kills to process (default: 5)
  """
  def debug_character_processing(character_index, opts \\ []) when is_integer(character_index) do
    # Get the kill limit from options
    kill_limit = Keyword.get(opts, :kill_limit, 5)

    # Get character info
    character_info =
      if character_index == 0 do
        # Use hardcoded debug character
        %{
          character_id: @debug_character_id,
          character_name: @debug_character_name
        }
      else
        # Get from tracked characters
        tracked_characters = Repository.get_tracked_characters()

        if length(tracked_characters) >= character_index do
          character = Enum.at(tracked_characters, character_index - 1)

          %{
            character_id: get_character_id(character),
            character_name: get_character_name(character)
          }
        else
          nil
        end
      end

    if character_info do
      process_all_character_kills(character_info, kill_limit)
    else
      AppLogger.kill_error("Character index out of bounds", %{
        index: character_index
      })

      {:error, :invalid_character_index}
    end
  end

  # Process all kills for a character with proper error handling
  defp process_all_character_kills(character_info, kill_limit) do
    character_id = character_info.character_id
    character_name = character_info.character_name

    AppLogger.kill_debug("Processing character kills", %{
      character_id: character_id,
      character_name: character_name,
      kill_limit: kill_limit
    })

    # Create context
    ctx =
      Context.new_historical(
        character_id,
        character_name,
        :debug,
        "debug-all-#{:os.system_time(:millisecond)}",
        skip_notification: false,
        force_notification: true
      )

    # Fetch kills from ZKill with limit
    case ZKillClient.get_character_kills(character_id, %{start: nil, end: nil}, kill_limit) do
      {:ok, kills} when is_list(kills) ->
        AppLogger.kill_debug("Processing #{length(kills)} kills", %{
          character_id: character_id,
          character_name: character_name
        })

        # Process each kill sequentially
        results =
          Enum.map(kills, fn raw_kill ->
            kill_id = Map.get(raw_kill, "killmail_id")

            AppLogger.kill_debug("Processing kill", %{
              kill_id: kill_id,
              character_id: character_id
            })

            try do
              # Transform raw kill data to KillmailData struct
              killmail_data =
                WandererNotifier.KillmailProcessing.Transformer.to_killmail_data(raw_kill)

              if is_nil(killmail_data) do
                AppLogger.kill_error("Failed to transform kill data to KillmailData", %{
                  kill_id: kill_id,
                  raw_data: inspect(raw_kill, limit: 200)
                })

                {kill_id, {:error, :invalid_kill_data}}
              else
                # Process the kill through the pipeline with properly structured data
                result = Pipeline.process_killmail(killmail_data, ctx)

                AppLogger.kill_debug("Kill processing result", %{
                  kill_id: kill_id,
                  success: match?({:ok, _}, result),
                  summary: "Process completed"
                })

                # Return a simplified tuple with kill_id and result status
                success = match?({:ok, _}, result)
                {kill_id, if(success, do: {:ok, "Success"}, else: {:error, "Failed"})}
              end
            rescue
              e ->
                AppLogger.kill_error("Exception processing kill", %{
                  kill_id: kill_id,
                  error: Exception.message(e)
                })

                {kill_id, {:error, Exception.message(e)}}
            end
          end)

        # Count successes and failures
        {successes, failures} =
          Enum.reduce(results, {0, 0}, fn {_, result}, {s, f} ->
            case result do
              {:ok, _} -> {s + 1, f}
              _ -> {s, f + 1}
            end
          end)

        AppLogger.kill_debug("Character processing complete", %{
          character_id: character_id,
          character_name: character_name,
          total: length(results),
          successes: successes,
          failures: failures
        })

        {:ok,
         %{
           total: length(results),
           succeeded: successes,
           failed: failures,
           results: results
         }}

      {:ok, []} ->
        AppLogger.kill_warn("No kills found for character", %{
          character_id: character_id,
          character_name: character_name
        })

        {:ok, %{total: 0, succeeded: 0, failed: 0, results: []}}

      {:error, reason} ->
        AppLogger.kill_error("Failed to fetch kills", %{
          character_id: character_id,
          character_name: character_name,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Process a single kill with detailed tracing of the pipeline.
  This is useful to see exactly what's happening inside the pipeline steps.

  ## Parameters
    - character_index: Index of character to use (0 for debug character)
    - opts: Additional options
  """
  def trace_pipeline_execution(character_index \\ 0, _opts \\ []) do
    AppLogger.kill_debug("Starting detailed pipeline trace", %{
      character_index: character_index
    })

    # Get character info
    character_info =
      if character_index == 0 do
        %{
          character_id: @debug_character_id,
          character_name: @debug_character_name
        }
      else
        # Get from tracked characters
        tracked_characters = Repository.get_tracked_characters()

        if length(tracked_characters) >= character_index do
          character = Enum.at(tracked_characters, character_index - 1)

          %{
            character_id: get_character_id(character),
            character_name: get_character_name(character)
          }
        else
          AppLogger.kill_error("Invalid character index, using debug character", %{
            index: character_index
          })

          %{
            character_id: @debug_character_id,
            character_name: @debug_character_name
          }
        end
      end

    character_id = character_info.character_id
    character_name = character_info.character_name

    # Create debug context with debug mode flag
    ctx =
      Context.new_historical(
        character_id,
        character_name,
        :debug,
        "trace-#{:os.system_time(:millisecond)}",
        skip_notification: false,
        force_notification: true,
        # Add a special flag for tracing
        detailed_trace: true
      )

    # Fetch kills from ZKill
    AppLogger.kill_debug("Fetching killmails for tracing", %{
      character_id: character_id,
      character_name: character_name
    })

    # Get kills from ZKill client directly
    case ZKillClient.get_character_kills(character_id, %{start: nil, end: nil}, 1) do
      {:ok, kills} when is_list(kills) and length(kills) > 0 ->
        # Get the first kill
        raw_kill = List.first(kills)
        kill_id = Map.get(raw_kill, "killmail_id")

        AppLogger.kill_debug("Tracing pipeline execution for kill", %{
          kill_id: kill_id,
          raw_keys: Map.keys(raw_kill)
        })

        # Enable debug tracing
        # :dbg module not available, commenting out tracing code
        # :dbg.tracer()
        # :dbg.p(:all, :c)
        # :dbg.tpl(WandererNotifier.KillmailProcessing.Pipeline, :process_killmail, :_)
        # :dbg.tpl(WandererNotifier.KillmailProcessing.Transformer, :to_killmail_data, :_)

        AppLogger.kill_debug("Note: Tracing functionality disabled (dbg module not available)")

        # Function to use for tracing the pipeline
        trace_pipeline_with_kill(raw_kill, ctx, kill_id)

      {:ok, []} ->
        AppLogger.kill_error("No kills found for tracing", %{
          character_id: character_id
        })

        {:error, :no_kills_found}

      {:error, reason} ->
        AppLogger.kill_error("Error fetching kills for tracing", %{
          character_id: character_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Helper to trace pipeline with a specific kill
  defp trace_pipeline_with_kill(raw_kill, ctx, kill_id) do
    try do
      AppLogger.kill_debug("Starting pipeline trace for kill #{kill_id}", %{
        character_id: ctx.character_id
      })

      # First transform the raw data
      AppLogger.kill_debug("Transforming raw kill data")
      killmail_data = WandererNotifier.KillmailProcessing.Transformer.to_killmail_data(raw_kill)

      if is_nil(killmail_data) do
        AppLogger.kill_error("Failed to transform kill data to KillmailData", %{
          kill_id: kill_id
        })

        {:error, :transform_failed}
      else
        # Now process through the pipeline
        AppLogger.kill_debug("Transformed kill data", %{
          kill_id: kill_id,
          struct_type: killmail_data.__struct__,
          keys: Map.keys(killmail_data)
        })

        # Log that we're about to call the real pipeline
        AppLogger.kill_debug("Calling REAL Pipeline.process_killmail function")

        # Process through the pipeline
        result = Pipeline.process_killmail(killmail_data, ctx)

        # Log the result
        AppLogger.kill_debug("Pipeline execution completed", %{
          kill_id: kill_id,
          success: match?({:ok, _}, result),
          summary: "Process completed"
        })

        # Clean up tracing
        # :dbg.stop_clear()

        # Return a simplified version of the result
        case result do
          {:ok, data} ->
            # Extract key information
            system_name = extract_system_name(data)
            victim_name = extract_victim_name(data)
            ship_name = extract_ship_name(data)
            persisted = Map.get(data, :persisted, false)
            notification_status = extract_notification_status(data)

            # Return simplified result
            {:ok,
             %{
               kill_id: kill_id,
               system: system_name,
               victim: victim_name,
               ship: ship_name,
               persisted: persisted,
               notification: notification_status
             }}

          error ->
            error
        end
      end
    rescue
      e ->
        stacktrace = __STACKTRACE__

        AppLogger.kill_error("Exception in pipeline trace", %{
          kill_id: kill_id,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(stacktrace)
        })

        # Clean up tracing
        # :dbg.stop_clear()

        {:error, {:exception, Exception.message(e)}}
    end
  end

  @doc """
  Directly process a specific killmail ID with minimal overhead.
  This is the most direct way to test the pipeline - fetches a kill and runs it
  through the real pipeline immediately.

  ## Parameters
    - killmail_id: The ID of the kill to process
  """
  def direct_process(killmail_id) do
    AppLogger.kill_debug("Starting direct processing of killmail #{killmail_id}")

    # Create debug context with the hardcoded debug character and force notification
    ctx =
      Context.new_historical(
        @debug_character_id,
        @debug_character_name,
        :debug,
        "direct-#{:os.system_time(:millisecond)}",
        skip_notification: false,
        force_notification: true
      )

    # Fetch the kill directly from ZKill
    case ZKillClient.get_single_killmail(killmail_id) do
      {:ok, kill} ->
        AppLogger.kill_debug("Successfully fetched killmail, passing directly to pipeline", %{
          kill_id: killmail_id
        })

        # Run it through the pipeline with no modification
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

            # Return a simplified result instead of the full KillmailData struct
            {:ok,
             %{
               killmail_id: killmail_id,
               success: true,
               duration_ms: duration_ms,
               system: system_name,
               victim: victim_name,
               ship: ship_name,
               persisted: processed_data.persisted,
               notification: notification_status
             }}

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
        AppLogger.kill_error("Failed to fetch killmail", %{
          kill_id: killmail_id,
          error: inspect(reason)
        })

        {:error, reason}
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

  @doc """
  Debug function that prints the tracked characters list from the cache,
  and checks whether a given character ID is tracked.
  """
  def debug_tracked_characters(character_id) do
    require WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

    # Get characters from the cache
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Convert character_id to string for consistent comparison
    character_id_str = to_string(character_id)

    # Log the contents of the characters list
    IO.puts("Tracked characters list (#{length(characters)} characters):")

    Enum.each(characters, fn char ->
      tracked_id =
        cond do
          is_map(char) && Map.has_key?(char, "character_id") ->
            to_string(char["character_id"])

          is_map(char) && Map.has_key?(char, :character_id) ->
            to_string(char.character_id)

          true ->
            "unknown structure: #{inspect(char)}"
        end

      char_name =
        cond do
          is_map(char) && Map.has_key?(char, "name") ->
            char["name"]

          is_map(char) && Map.has_key?(char, :name) ->
            char.name

          is_map(char) && Map.has_key?(char, "character_name") ->
            char["character_name"]

          is_map(char) && Map.has_key?(char, :character_name) ->
            char.character_name

          true ->
            "unknown"
        end

      IO.puts("  Character: #{char_name} (ID: #{tracked_id})")
    end)

    # Check if our character is tracked
    is_tracked =
      Enum.any?(characters, fn char ->
        # Extract character_id in a fault-tolerant way
        tracked_id =
          cond do
            is_map(char) && Map.has_key?(char, "character_id") ->
              to_string(char["character_id"])

            is_map(char) && Map.has_key?(char, :character_id) ->
              to_string(char.character_id)

            true ->
              nil
          end

        # Compare as strings
        tracked_id && tracked_id == character_id_str
      end)

    # Also check individual tracking keys
    direct_cache_key = CacheKeys.tracked_character(character_id_str)
    direct_tracking = CacheRepo.get(direct_cache_key) != nil

    IO.puts("\nVerifying tracking status for character ID #{character_id}:")
    IO.puts("  - Is in list: #{is_tracked}")
    IO.puts("  - Has direct cache key: #{direct_tracking}")
    IO.puts("  - Direct cache key: #{direct_cache_key}")

    # Now check from the notification determiner's perspective
    alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
    determiner_tracking = KillDeterminer.tracked_character?(character_id)

    IO.puts("  - KillDeterminer.tracked_character?: #{determiner_tracking}")

    # Return the tracking status
    %{
      characters_count: length(characters),
      is_tracked: is_tracked,
      direct_tracking: direct_tracking,
      determiner_tracking: determiner_tracking
    }
  end

  @doc """
  Debug function that checks why a kill is marked as "not tracked" by running
  through the same determination logic as the pipeline.
  """
  def debug_kill_notification(kill_id) do
    # Get the killmail from ESI for the ID
    kill_data_response = do_get_kill(kill_id)

    # If successful
    case kill_data_response do
      {:ok, raw_killmail} ->
        IO.puts("🧪 Debugging kill #{kill_id}")

        # Transform to KillmailData for consistent processing
        alias WandererNotifier.KillmailProcessing.Transformer
        alias WandererNotifier.KillmailProcessing.{Context, Pipeline}
        alias WandererNotifier.KillmailProcessing.Extractor
        alias WandererNotifier.Resources.Killmail

        # First log the raw structure
        IO.puts("\n📦 RAW KILLMAIL STRUCTURE:")
        # Check for attackers
        attackers = Map.get(raw_killmail, "attackers") || Map.get(raw_killmail, :attackers) || []
        IO.puts("  Found #{length(attackers)} attackers in raw killmail")

        # Check for victim
        has_victim = Map.has_key?(raw_killmail, "victim") || Map.has_key?(raw_killmail, :victim)
        IO.puts("  Has victim: #{has_victim}")

        # Now transform to standard format
        killmail_data = Transformer.to_killmail_data(raw_killmail)

        if is_nil(killmail_data) do
          IO.puts("❌ Failed to transform killmail to KillmailData struct!")
          return_diagnosis_error(kill_id, "Transform failed")
        else
          # Log structure after transformation
          IO.puts("\n📦 TRANSFORMED KILLMAIL STRUCTURE:")
          transformed_attackers = Extractor.get_attackers(killmail_data)

          IO.puts(
            "  Found #{length(transformed_attackers)} attackers using Extractor.get_attackers"
          )

          # Create context for processing
          ctx =
            Context.new_historical(
              # Debug character
              1_406_208_348,
              "Debug Character",
              :debug,
              "debug-pipeline-#{:os.system_time(:millisecond)}",
              # Don't actually send notifications
              skip_notification: true,
              # Don't force notifications
              force_notification: false
            )

          # Process through standard pipeline
          IO.puts("\n🔄 PROCESSING THROUGH PIPELINE:")
          start_time = :os.system_time(:millisecond)
          result = Pipeline.process_killmail(killmail_data, ctx)
          end_time = :os.system_time(:millisecond)

          # After pipeline processing, examine the killmail structure again
          # to see if attackers were added by enrichment
          IO.puts("\n📦 EXAMINING RESULT STRUCTURE AFTER PIPELINE:")

          # Check result structure
          case result do
            {:ok, processed_data} ->
              IO.puts("✅ Pipeline processing successful (took #{end_time - start_time}ms)")

              # Check if the data is a struct and what type
              data_type =
                if is_struct(processed_data),
                  do: "#{processed_data.__struct__}",
                  else: if(is_map(processed_data), do: "map", else: "other")

              IO.puts("  Result type: #{data_type}")

              # Try to get attackers through different methods to debug
              attackers1 =
                if is_map(processed_data), do: Map.get(processed_data, :attackers), else: nil

              esi_data =
                if is_map(processed_data), do: Map.get(processed_data, :esi_data), else: %{}

              attackers2 = if is_map(esi_data), do: Map.get(esi_data, "attackers"), else: nil
              attackers3 = Extractor.get_attackers(processed_data)

              IO.puts("  direct [:attackers] access: #{length(attackers1 || [])}")
              IO.puts("  [:esi_data][\"attackers\"] access: #{length(attackers2 || [])}")
              IO.puts("  Extractor.get_attackers result: #{length(attackers3 || [])}")

              # Check the top-level keys
              top_keys = if is_map(processed_data), do: Map.keys(processed_data), else: []
              IO.puts("  Top-level keys: #{inspect(Enum.take(top_keys, 10))}...")

              # Check for attacker_count which should be set during enrichment
              attacker_count =
                if is_map(processed_data), do: Map.get(processed_data, :attacker_count), else: nil

              IO.puts("  :attacker_count field: #{inspect(attacker_count)}")

              # Check for :persisted flag
              persisted = Map.get(processed_data, :persisted, false)
              IO.puts("  :persisted field: #{inspect(persisted)}")

              # Check for metadata
              metadata = Map.get(processed_data, :metadata, %{})
              IO.puts("  :metadata field: #{inspect(metadata, limit: 5)}")

              # Get the reason for non-persistence
              reason = extract_not_persisted_reason(processed_data)
              IO.puts("  Not persisted reason: #{inspect(reason)}")

              # Check to see if required fields for persistence were present or missing
              IO.puts("\n🔍 CHECKING FOR REQUIRED KILLMAIL FIELDS:")

              required_fields = [
                :killmail_id,
                :processed_at,
                :solar_system_security
              ]

              Enum.each(required_fields, fn field ->
                value = Map.get(processed_data, field)
                IO.puts("  #{field}: #{inspect(value)}")
              end)

              # Now explicitly query the database for the killmail
              IO.puts("\n🔍 CHECKING DATABASE FOR PERSISTED RECORDS:")

              # Check if the killmail was persisted to the database
              require Ash.Query
              alias WandererNotifier.Resources.Killmail
              alias WandererNotifier.KillmailProcessing.KillmailQueries

              # Determine if we have a UUID or integer killmail_id
              is_uuid =
                is_binary(kill_id) &&
                  String.match?(
                    kill_id,
                    ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
                  )

              id_type =
                cond do
                  is_uuid -> "UUID (record ID)"
                  is_integer(kill_id) -> "integer (killmail_id)"
                  is_binary(kill_id) -> "string (probably killmail_id)"
                  true -> "unknown format"
                end

              IO.puts("  Killmail ID format: #{kill_id} (#{id_type})")

              # Ensure we have an integer kill_id for database queries
              _kill_id_int =
                cond do
                  is_integer(kill_id) ->
                    kill_id

                  is_binary(kill_id) ->
                    case Integer.parse(kill_id) do
                      {int_id, _} ->
                        int_id

                      :error ->
                        IO.puts("  ⚠️ Warning: kill_id is not in integer format: #{kill_id}")
                        # keep original to avoid errors in other places
                        kill_id
                    end

                  true ->
                    IO.puts(
                      "  ⚠️ Warning: kill_id is not an integer or string: #{inspect(kill_id)}"
                    )

                    kill_id
                end

              IO.puts("  Using killmail_id for queries: #{kill_id}")

              # First check if we can even access the Killmail Resource
              IO.puts("📋 Attempting to access Killmail Resource:")

              killmail_module_exists = Code.ensure_loaded?(Killmail)

              if killmail_module_exists do
                IO.puts("  ✅ Killmail module exists and is loaded")
              else
                IO.puts("  ❌ Killmail module doesn't exist or can't be loaded")
              end

              # Check if the killmail exists in the database
              killmail_exists =
                try do
                  # KillmailQueries.exists? handles both UUID and integer formats now
                  KillmailQueries.exists?(kill_id)
                rescue
                  e ->
                    IO.puts("  ❌ Error checking if killmail exists: #{Exception.message(e)}")
                    false
                end

              IO.puts("  Killmail exists in database: #{killmail_exists}")

              # Only try to get details if we know it exists
              if killmail_exists do
                # Use KillmailQueries.get instead of direct Ash query
                # The get function now handles both UUID and integer formats
                killmail_record_query =
                  try do
                    KillmailQueries.get(kill_id)
                  rescue
                    e ->
                      IO.puts("  ❌ Error creating database query: #{Exception.message(e)}")
                      {:error, :query_error}
                  end

                case killmail_record_query do
                  {:ok, killmail} ->
                    IO.puts("  ✅ Killmail record found in database:")
                    IO.puts("  ID (UUID): #{killmail.id}")
                    IO.puts("  Killmail ID (integer): #{killmail.killmail_id}")
                    IO.puts("  Victim: #{killmail.victim_name || "unknown"}")
                    IO.puts("  System: #{killmail.solar_system_name || "unknown"}")
                    IO.puts("  Attacker count: #{killmail.attacker_count || 0}")

                    # Now look for character involvements
                    involvement_records =
                      try do
                        # Extract the integer killmail_id from the record - NOT the UUID id field
                        numeric_killmail_id = killmail.killmail_id

                        IO.puts("\n  ⚠️ Important: Must use the correct ID for involvement query:")
                        IO.puts("    - ❌ DO NOT USE: Record ID (UUID): #{killmail.id}")

                        IO.puts(
                          "    - ✅ CORRECTLY USING: Integer killmail_id: #{numeric_killmail_id}"
                        )

                        # Use the get_involvements function with the integer killmail_id
                        result = KillmailQueries.get_involvements(numeric_killmail_id)

                        # Log success
                        IO.puts(
                          "  ✅ Successfully executed get_involvements query with integer killmail_id"
                        )

                        # Return the result
                        result
                      rescue
                        e ->
                          IO.puts(
                            "  ❌ Error querying character involvements: #{Exception.message(e)}"
                          )

                          # Print stack trace for better debugging
                          IO.puts("  Stack trace: #{Exception.format_stacktrace(__STACKTRACE__)}")

                          {:error, :query_error}
                      end

                    case involvement_records do
                      {:ok, involvements}
                      when is_list(involvements) and length(involvements) > 0 ->
                        IO.puts(
                          "\n  ✅ Found #{length(involvements)} character involvement records:"
                        )

                        Enum.each(involvements, fn involvement ->
                          IO.puts(
                            "    Character ID: #{involvement.character_id} - Role: #{involvement.character_role}"
                          )

                          IO.puts("      Ship: #{involvement.ship_type_name || "unknown"}")

                          # Safely print is_final_blow - check if it's an Ash.NotLoaded struct
                          final_blow_value =
                            case involvement.is_final_blow do
                              %Ash.NotLoaded{} -> "not loaded"
                              value -> "#{value}"
                            end

                          IO.puts("      Final blow: #{final_blow_value}")
                        end)

                      {:ok, []} ->
                        IO.puts("\n  ❓ No character involvement records found for this killmail")

                      {:error, reason} ->
                        IO.puts("\n  ❌ Error querying character involvements: #{inspect(reason)}")

                      error ->
                        IO.puts(
                          "\n  ❌ Unknown error querying character involvements: #{inspect(error)}"
                        )
                    end

                  {:error, :not_found} ->
                    IO.puts("  ❌ No killmail record found in database - persistence failed")
                    IO.puts("  This confirms the killmail was not persisted")

                  {:error, reason} ->
                    IO.puts("  ❌ Error querying killmail record: #{inspect(reason)}")

                  error ->
                    IO.puts("  ❌ Unknown error in database query: #{inspect(error)}")
                end
              else
                IO.puts("  ❌ Killmail not found in database - persistence failed")
              end

              # Return simplified result
              %{
                killmail_id: kill_id,
                success: true,
                persisted: persisted,
                duration_ms: end_time - start_time,
                attacker_count: attacker_count,
                not_persisted_reason: reason
              }

            error ->
              IO.puts("❌ Pipeline processing failed (took #{end_time - start_time}ms)")
              IO.puts("  Error: #{inspect(error)}")

              %{
                killmail_id: kill_id,
                success: false,
                error: inspect(error)
              }
          end
        end

      {:error, reason} ->
        IO.puts("Failed to fetch killmail #{kill_id}: #{inspect(reason)}")
        return_diagnosis_error(kill_id, reason)
    end
  end

  @doc """
  Detailed diagnostic function to analyze character tracking detection issues.
  This function examines all the steps in the character tracking detection process
  to identify why a character that should be tracked isn't being recognized.

  ## Parameters
    - character_id: The ID of the character to analyze
  """
  def diagnose_tracking_issue(character_id) do
    require WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer

    # Convert character_id to string for consistent comparison
    character_id_str = to_string(character_id)

    IO.puts("\n===== TRACKING DETECTION DIAGNOSIS =====")
    IO.puts("Analyzing tracking detection for character ID #{character_id_str}")

    # 1. Check direct cache key (this is what KillDeterminer actually uses)
    tracked_key = CacheKeys.tracked_character(character_id_str)
    is_direct_tracked = CacheRepo.get(tracked_key) != nil

    IO.puts("\nStep 1: Direct tracked key check")
    IO.puts("  Key: #{tracked_key}")
    IO.puts("  Value exists: #{is_direct_tracked}")

    if is_direct_tracked do
      IO.puts("  ✅ Character has direct tracking key, should be recognized as tracked")
      direct_value = CacheRepo.get(tracked_key)
      IO.puts("  Stored value: #{inspect(direct_value)}")
    else
      IO.puts("  ❌ Character doesn't have direct tracking key, won't be recognized as tracked")
    end

    # 2. Check character list cache
    character_list_key = CacheKeys.character_list()
    character_list = CacheRepo.get(character_list_key) || []

    IO.puts("\nStep 2: Character list check")
    IO.puts("  Key: #{character_list_key}")
    IO.puts("  List exists: #{character_list != []}")
    IO.puts("  List length: #{length(character_list)}")

    # Look for the character in the list
    matching_char =
      Enum.find(character_list, fn char ->
        char_id =
          cond do
            is_map(char) && Map.has_key?(char, "character_id") -> to_string(char["character_id"])
            is_map(char) && Map.has_key?(char, :character_id) -> to_string(char.character_id)
            true -> nil
          end

        char_id == character_id_str
      end)

    if matching_char do
      IO.puts("  ✅ Character found in character list")
      IO.puts("  Character data: #{inspect(matching_char)}")
    else
      IO.puts("  ❌ Character not found in character list")

      # Show sample of list for debugging
      sample = Enum.take(character_list, min(3, length(character_list)))
      IO.puts("  Sample from list: #{inspect(sample)}")
    end

    # 3. Test KillDeterminer.tracked_character? directly
    determiner_tracked = KillDeterminer.tracked_character?(character_id)

    IO.puts("\nStep 3: KillDeterminer.tracked_character? test")
    IO.puts("  Result: #{determiner_tracked}")

    if determiner_tracked do
      IO.puts("  ✅ KillDeterminer recognizes this character as tracked")
    else
      IO.puts("  ❌ KillDeterminer does NOT recognize this character as tracked")
    end

    # 4. Test character info lookup
    character_info_key = CacheKeys.character(character_id_str)
    character_info = CacheRepo.get(character_info_key)

    IO.puts("\nStep 4: Character info check")
    IO.puts("  Key: #{character_info_key}")
    IO.puts("  Info exists: #{character_info != nil}")

    if character_info do
      IO.puts("  Character info: #{inspect(character_info)}")
    end

    # 5. Check killmail processing for this character
    IO.puts("\nStep 5: Testing kill tracking with a new killmail")
    IO.puts("  Running a test using direct_process to check if tracking is working...")

    # Try to process a kill with this function
    _ctx =
      WandererNotifier.KillmailProcessing.Context.new_historical(
        character_id,
        "Diagnostic Character",
        :debug,
        "diagnostic-#{:os.system_time(:millisecond)}",
        skip_notification: true,
        force_notification: false
      )

    # Return diagnosis result
    %{
      character_id: character_id,
      direct_tracking_key: tracked_key,
      is_directly_tracked: is_direct_tracked,
      in_character_list: matching_char != nil,
      determiner_tracked: determiner_tracked,
      character_info_key: character_info_key,
      has_character_info: character_info != nil
    }
  end

  @doc """
  Diagnostic function to analyze why a specific killmail isn't being tracked or notified properly.
  This function examines the killmail and traces through the detection logic step by step.

  ## Parameters
    - killmail_id: The ID of the killmail to analyze
  """
  def diagnose_killmail_tracking(killmail_id) do
    require WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
    alias WandererNotifier.KillmailProcessing.{Pipeline, Transformer}
    alias WandererNotifier.Logger.Logger, as: AppLogger

    IO.puts("\n===== KILLMAIL TRACKING DIAGNOSIS =====")
    IO.puts("Analyzing tracking detection for killmail ID #{killmail_id}")

    # 1. Fetch the killmail to analyze
    case ZKillClient.get_single_killmail(killmail_id) do
      {:ok, raw_kill} ->
        IO.puts("\nStep 1: Successfully fetched killmail #{killmail_id}")

        # Examine raw killmail structure
        IO.puts("\nStep 1a: Raw killmail structure overview:")

        IO.puts(
          "  Has 'victim' key: #{Map.has_key?(raw_kill, "victim") || Map.has_key?(raw_kill, :victim)}"
        )

        IO.puts(
          "  Has 'attackers' key: #{Map.has_key?(raw_kill, "attackers") || Map.has_key?(raw_kill, :attackers)}"
        )

        IO.puts(
          "  Has 'killmail_id' key: #{Map.has_key?(raw_kill, "killmail_id") || Map.has_key?(raw_kill, :killmail_id)}"
        )

        IO.puts(
          "  Has 'zkb' key: #{Map.has_key?(raw_kill, "zkb") || Map.has_key?(raw_kill, :zkb)}"
        )

        IO.puts("  Raw kill top-level keys: #{inspect(Map.keys(raw_kill))}")

        try do
          # Enable additional deep debug logging
          setup_debug_logging()

          # 2. Run the direct_process function which uses the same pipeline
          IO.puts("\nStep 2: Running direct_process to process through real pipeline...")
          result = direct_process_with_debug(killmail_id)

          # Analyze the result
          IO.puts("\nStep 3: Analyzing result from pipeline...")

          case result do
            {:ok, processed_data} ->
              persisted = Map.get(processed_data, :persisted, false)
              IO.puts("  Kill persisted: #{persisted}")

              if !persisted do
                reason = extract_not_persisted_reason(processed_data)
                IO.puts("  Not persisted reason: #{reason || "unknown"}")
              end

              # Return detailed diagnostic info
              %{
                killmail_id: killmail_id,
                success: true,
                processed: true,
                persisted: persisted,
                not_persisted_reason: extract_not_persisted_reason(processed_data),
                notification_status: extract_notification_status(processed_data)
              }

            error ->
              IO.puts("  Error processing killmail: #{inspect(error)}")

              %{
                killmail_id: killmail_id,
                success: false,
                error: inspect(error)
              }
          end
        rescue
          e ->
            stacktrace = Exception.format_stacktrace(__STACKTRACE__)

            IO.puts("\nERROR during diagnosis: #{Exception.message(e)}")
            IO.puts("Stacktrace: #{stacktrace}")

            %{
              killmail_id: killmail_id,
              success: false,
              error: Exception.message(e),
              stacktrace: stacktrace
            }
        end

      {:error, reason} ->
        IO.puts("❌ Failed to fetch killmail #{killmail_id}: #{inspect(reason)}")
        return_diagnosis_error(killmail_id, reason)
    end
  end

  # Helper for error case
  defp return_diagnosis_error(killmail_id, reason) do
    %{
      killmail_id: killmail_id,
      success: false,
      error: reason
    }
  end

  # Helper to fetch a killmail by ID
  defp do_get_kill(kill_id) do
    alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
    alias WandererNotifier.Logger.Logger, as: AppLogger

    # Convert to integer if it's a string
    kill_id_int =
      cond do
        is_integer(kill_id) ->
          kill_id

        is_binary(kill_id) ->
          case Integer.parse(kill_id) do
            {int_id, _} ->
              int_id

            :error ->
              IO.puts("⚠️ Warning: kill_id is not in integer format: #{kill_id}")
              # Try to continue with original value
              kill_id
          end

        true ->
          IO.puts("⚠️ Warning: kill_id is not an integer or string: #{inspect(kill_id)}")
          # Try to continue with original value
          kill_id
      end

    IO.puts("🔍 Fetching killmail #{kill_id_int} from ZKill API")

    # Fetch the kill from ZKill API
    ZKillClient.get_single_killmail(kill_id_int)
  end

  # Set up additional debug logging
  defp setup_debug_logging do
    # Set any required process dictionary flags for detailed logging
    Process.put(:debug_tracking_detection, true)
    Process.put(:trace_killmail_processing, true)

    # Any other setup that might be needed
    :ok
  end

  # Version of direct_process with enhanced debugging
  defp direct_process_with_debug(killmail_id) do
    alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
    alias WandererNotifier.KillmailProcessing.{Context, Pipeline}
    alias WandererNotifier.Logger.Logger, as: AppLogger
    alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
    alias WandererNotifier.KillmailProcessing.KillmailQueries

    AppLogger.kill_debug("Starting debug direct processing of killmail #{killmail_id}")

    # Ensure we have an integer killmail_id
    killmail_id_int =
      cond do
        is_integer(killmail_id) ->
          killmail_id

        is_binary(killmail_id) ->
          case Integer.parse(killmail_id) do
            {int_id, _} ->
              int_id

            :error ->
              AppLogger.kill_debug("Warning: killmail_id is not in integer format", %{
                killmail_id: killmail_id
              })

              killmail_id
          end

        true ->
          AppLogger.kill_debug("Warning: killmail_id is not an integer or string", %{
            killmail_id: killmail_id
          })

          killmail_id
      end

    # Extract KillDeterminer function reference for monkey patching
    _original_has_tracked_character = &KillDeterminer.has_tracked_character?/1

    # Create debug context with debug logging flags
    ctx =
      Context.new_historical(
        @debug_character_id,
        @debug_character_name,
        :debug,
        "direct-debug-#{:os.system_time(:millisecond)}",
        skip_notification: false,
        force_notification: false,
        debug_tracking: true
      )

    # Set up a patch for the KillDeterminer.has_tracked_character? function
    # The override will log detailed information about what it's checking
    try do
      # Check if the killmail exists using KillmailQueries
      killmail_exists = KillmailQueries.exists?(killmail_id_int)

      AppLogger.kill_debug("Killmail database check", %{
        killmail_id: killmail_id_int,
        exists_in_database: killmail_exists
      })

      # Fetch the kill directly from ZKill
      case ZKillClient.get_single_killmail(killmail_id_int) do
        {:ok, kill} ->
          AppLogger.kill_debug("Successfully fetched killmail for debugging", %{
            kill_id: killmail_id_int,
            data_type: typeof(kill),
            top_level_keys: Map.keys(kill)
          })

          # Check if it has attackers/victim before pipeline
          check_raw_kill_structure(kill)

          # Run it through the pipeline with logging
          result = Pipeline.process_killmail(kill, ctx)

          # Return the result
          result

        {:error, reason} ->
          AppLogger.kill_error("Failed to fetch killmail for debugging", %{
            kill_id: killmail_id_int,
            error: inspect(reason)
          })

          {:error, reason}
      end
    after
      # Restore original function
      # Process.delete(:has_tracked_character_fn)
      :ok
    end
  end

  # Helper to check raw kill structure
  defp check_raw_kill_structure(kill) do
    alias WandererNotifier.Logger.Logger, as: AppLogger

    # Check for attackers
    attackers = Map.get(kill, "attackers") || Map.get(kill, :attackers) || []
    attackers_count = length(attackers)

    # Check for victim
    has_victim = Map.has_key?(kill, "victim") || Map.has_key?(kill, :victim)

    # Log findings
    AppLogger.kill_debug("Raw kill structure check", %{
      has_victim_key: has_victim,
      attackers_count: attackers_count,
      has_zkb: Map.has_key?(kill, "zkb") || Map.has_key?(kill, :zkb),
      has_system_id: Map.has_key?(kill, "solar_system_id") || Map.has_key?(kill, :solar_system_id)
    })

    # If we have attackers, examine the first one
    if attackers_count > 0 do
      sample_attacker = List.first(attackers)

      AppLogger.kill_debug("Sample attacker data", %{
        data: inspect(sample_attacker, limit: 200),
        has_character_id:
          Map.has_key?(sample_attacker, "character_id") ||
            Map.has_key?(sample_attacker, :character_id)
      })
    end
  end
end
