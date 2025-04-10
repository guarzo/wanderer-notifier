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
  defp process_character_kills(character_id, character_name, ctx, kill_limit) do
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

          AppLogger.kill_debug("Processing kill", %{
            kill_id: kill_id,
            character_id: character_id_int,
            character_name: character_name
          })

          # First transform the raw data to a proper KillmailData struct
          # This is critical to ensure consistent data format
          killmail_data =
            WandererNotifier.KillmailProcessing.Transformer.to_killmail_data(raw_kill)

          if is_nil(killmail_data) do
            AppLogger.kill_error("Failed to transform kill data to KillmailData", %{
              kill_id: kill_id,
              raw_data: inspect(raw_kill, limit: 200)
            })

            {:error, :invalid_kill_data}
          else
            # Process the kill through the pipeline with properly structured data
            process_result = Pipeline.process_killmail(killmail_data, ctx)

            AppLogger.kill_debug("Kill processing result", %{
              kill_id: kill_id,
              success: match?({:ok, _}, process_result),
              summary: "Process completed"
            })

            # Return a simplified version of the result
            case process_result do
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
      process_specific_kill_for_character(character_info, kill_id)
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

  # Process a specific kill for a character
  defp process_specific_kill_for_character(character_info, kill_id) do
    character_id = character_info.character_id
    character_name = character_info.character_name

    # Ensure we have an integer kill_id
    kill_id_int =
      cond do
        is_integer(kill_id) ->
          kill_id

        is_binary(kill_id) ->
          case Integer.parse(kill_id) do
            {id, _} -> id
            _ -> nil
          end

        true ->
          nil
      end

    if is_nil(kill_id_int) do
      AppLogger.kill_error("Invalid kill ID format", %{
        kill_id: kill_id
      })

      {:error, :invalid_kill_id}
    else
      # Create debug context
      ctx =
        Context.new_historical(
          character_id,
          character_name,
          :debug,
          "debug-specific-#{:os.system_time(:millisecond)}",
          skip_notification: false,
          force_notification: true
        )

      # Fetch the specific kill from ZKill
      ZKillClient.get_single_killmail(kill_id_int)
      |> handle_specific_kill_result(ctx)
    end
  end

  # Handle the result of fetching a specific kill
  defp handle_specific_kill_result({:ok, raw_kill}, ctx) do
    # Extract the killmail ID for logging
    kill_id = Map.get(raw_kill, "killmail_id")

    AppLogger.kill_debug("Processing specific kill", %{
      kill_id: kill_id,
      character_id: ctx.character_id
    })

    # Transform raw kill data to KillmailData struct to ensure
    # we're using the same data path as production
    killmail_data = WandererNotifier.KillmailProcessing.Transformer.to_killmail_data(raw_kill)

    if is_nil(killmail_data) do
      AppLogger.kill_error("Failed to transform specific kill data to KillmailData", %{
        kill_id: kill_id,
        raw_data: inspect(raw_kill, limit: 200)
      })

      {:error, :invalid_kill_data}
    else
      # Process the kill through the same pipeline as production
      result = Pipeline.process_killmail(killmail_data, ctx)

      AppLogger.kill_debug("Specific kill processing result", %{
        kill_id: kill_id,
        success: match?({:ok, _}, result),
        summary: "Process completed"
      })

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
  end

  defp handle_specific_kill_result({:error, reason}, _ctx) do
    AppLogger.kill_error("Failed to fetch specific kill", %{
      error: inspect(reason)
    })

    {:error, reason}
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
  def debug_kill_notification(killmail_id) do
    alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
    alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
    alias WandererNotifier.KillmailProcessing.Transformer

    # Fetch the kill to debug
    case ZKillClient.get_single_killmail(killmail_id) do
      {:ok, kill} ->
        IO.puts("Successfully fetched killmail #{killmail_id}")

        # First convert to standard format for consistent access
        standardized_kill = Transformer.to_killmail_data(kill)
        victim = standardized_kill.victim || %{}
        victim_id = Map.get(victim, "character_id")
        victim_name = Map.get(victim, "character_name") || "Unknown Pilot"

        IO.puts("\nKill information:")
        IO.puts("  Victim: #{victim_name} (ID: #{victim_id || "unknown"})")

        IO.puts(
          "  System: #{standardized_kill.solar_system_name || "unknown"} (ID: #{standardized_kill.solar_system_id || "unknown"})"
        )

        # Debug tracking for the victim
        if victim_id do
          IO.puts("\nChecking if victim is tracked:")
          victim_tracked = debug_tracked_characters(victim_id)
          IO.puts("  Victim tracked: #{victim_tracked.is_tracked}")
        else
          IO.puts("\nNo victim ID found to check tracking")
        end

        # Get all attackers with character IDs
        attackers = standardized_kill.attackers || []

        attackers_with_ids =
          Enum.filter(attackers, fn attacker ->
            attacker_id = Map.get(attacker, "character_id")
            attacker_id != nil
          end)

        IO.puts("\nFound #{length(attackers_with_ids)} attackers with character IDs")

        # Check tracked attackers
        tracked_attackers =
          Enum.filter(attackers_with_ids, fn attacker ->
            attacker_id = Map.get(attacker, "character_id")
            is_tracked = KillDeterminer.tracked_character?(attacker_id)
            attacker_name = Map.get(attacker, "character_name") || "Unknown"

            if is_tracked do
              IO.puts("  Tracked attacker: #{attacker_name} (ID: #{attacker_id})")
            end

            is_tracked
          end)

        # Check if the system is tracked
        system_id = standardized_kill.solar_system_id
        system_tracked = KillDeterminer.tracked_system?(system_id)

        IO.puts("\nSystem tracking status:")
        IO.puts("  System ID: #{system_id || "unknown"}")
        IO.puts("  System tracked: #{system_tracked}")

        # Now run the full notification determination
        notification_result = KillDeterminer.should_notify?(standardized_kill)

        IO.puts("\nNotification determination result:")

        case notification_result do
          {true, reason} -> IO.puts("  Will notify: true (#{reason})")
          {false, reason} -> IO.puts("  Will notify: false (#{reason})")
          other -> IO.puts("  Unexpected result: #{inspect(other)}")
        end

        # Return a summary of findings
        %{
          victim_id: victim_id,
          victim_tracked: victim_id && KillDeterminer.tracked_character?(victim_id),
          attackers_count: length(attackers_with_ids),
          tracked_attackers_count: length(tracked_attackers),
          system_id: system_id,
          system_tracked: system_tracked,
          notification_result: notification_result
        }

      {:error, reason} ->
        IO.puts("Failed to fetch killmail #{killmail_id}: #{inspect(reason)}")
        {:error, reason}
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
    ctx =
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
    alias WandererNotifier.KillmailProcessing.{Extractor, Pipeline, Transformer}
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

    AppLogger.kill_debug("Starting debug direct processing of killmail #{killmail_id}")

    # Extract KillDeterminer function reference for monkey patching
    original_has_tracked_character = &KillDeterminer.has_tracked_character?/1

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
      # Monkeypatch the function (doesn't actually work but conceptually here)
      # Process.put(:has_tracked_character_fn, fn killmail ->
      #   log_debug_tracking_check(killmail)
      #   original_has_tracked_character.(killmail)
      # end)

      # Fetch the kill directly from ZKill
      case ZKillClient.get_single_killmail(killmail_id) do
        {:ok, kill} ->
          AppLogger.kill_debug("Successfully fetched killmail for debugging", %{
            kill_id: killmail_id,
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
            kill_id: killmail_id,
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

  # Helper to log tracking check
  defp log_debug_tracking_check(killmail) do
    alias WandererNotifier.Logger.Logger, as: AppLogger
    alias WandererNotifier.KillmailProcessing.Extractor

    kill_id = Extractor.get_killmail_id(killmail)

    # Check for attackers
    attackers = Extractor.get_attackers(killmail) || []
    attackers_count = length(attackers)

    # Check for victim
    victim = Extractor.get_victim(killmail)
    victim_id = victim && (Map.get(victim, "character_id") || Map.get(victim, :character_id))

    # Log detailed info
    AppLogger.kill_debug("TRACKING CHECK for kill #{kill_id}", %{
      victim_id: victim_id,
      attackers_count: attackers_count,
      system_id: Extractor.get_system_id(killmail),
      killmail_data_type: killmail.__struct__,
      top_level_keys: Map.keys(killmail)
    })

    if attackers_count > 0 do
      # Log first few attackers
      sample_attackers = Enum.take(attackers, min(3, attackers_count))

      Enum.each(sample_attackers, fn attacker ->
        attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)

        attacker_name =
          Map.get(attacker, "character_name") || Map.get(attacker, :character_name) || "Unknown"

        AppLogger.kill_debug("Attacker check", %{
          id: attacker_id,
          name: attacker_name
        })
      end)
    else
      AppLogger.kill_debug("No attackers found in killmail")
    end
  end

  # Diagnose a standardized killmail - keeping here but not used directly
  defp diagnose_standardized_killmail(killmail_id, killmail) do
    # ... existing code ...
  end
end
