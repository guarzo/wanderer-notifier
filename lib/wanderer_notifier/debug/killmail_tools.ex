# credo:disable-for-this-file
defmodule WandererNotifier.Debug.KillmailTools do
  @moduledoc """
  Debugging tools for analyzing killmail processing and notifications.
  Provides functions to force notification delivery and detailed logging
  regardless of tracking status.
  """

  alias WandererNotifier.KillmailProcessing.{
    Context,
    KillmailData
  }

  alias WandererNotifier.Processing.Killmail.Core
  alias WandererNotifier.Processing.Killmail.KillmailProcessor

  @doc """
  Enable detailed logging for the next killmail received.

  This will log detailed information about the killmail data,
  showing full structure and processing details.

  ## Returns
  * `:ok` - Logging for next killmail has been enabled
  """
  def log_next_killmail do
    # Set a flag in application env to enable logging
    Application.put_env(:wanderer_notifier, :log_next_killmail, true)

    IO.puts("""

    🔍 Next killmail will be logged with detailed information.

    Watch for console output showing:
     - Full killmail structure
     - Processing data and decisions
     - Notification eligibility details
     - Validation results

    This happens automatically when the next killmail is received.
    """)

    :ok
  end

  @doc """
  Enable detailed logging AND force notification for the next killmail received.
  This overrides the normal tracking criteria and forces the notification to be processed.

  ## Returns
  * `:ok` - Logging and forced notification for next killmail has been enabled
  """
  def notify_next_killmail do
    # Set flags in application env
    Application.put_env(:wanderer_notifier, :log_next_killmail, true)
    Application.put_env(:wanderer_notifier, :force_notify_next_killmail, true)

    IO.puts("""

    🔔 Next killmail will be logged with detailed information AND will be force-notified.

    Watch for console output showing:
     - Full killmail structure and processing data
     - Notification details regardless of tracked status

    This happens automatically when the next killmail is received.
    """)

    :ok
  end

  @doc """
  Process a killmail for debugging persistence.
  This function is called by the websocket handler when a killmail is received
  and debug logging is enabled.
  """
  def process_killmail_debug(json_data) when is_map(json_data) do
    kill_id = extract_killmail_id(json_data)

    IO.puts("\n=====================================================")
    IO.puts("🔍 ANALYZING KILLMAIL #{kill_id} FOR PROCESSING")
    IO.puts("=====================================================\n")

    # Log the full raw killmail for complete inspection
    IO.puts("------ FULL RAW KILLMAIL DATA ------")
    IO.puts(Jason.encode!(json_data, pretty: true))
    IO.puts("\n")

    # Convert json_data to a format suitable for validation
    killmail_data = %WandererNotifier.Killmail.Core.Data{
      killmail_id: kill_id,
      raw_zkb_data: Map.get(json_data, "zkb", %{}),
      raw_esi_data:
        Map.drop(json_data, ["zkb", "killmail_id"])
        |> Map.put("solar_system_name", json_data["solar_system_name"] || "Unknown System")
    }

    # Show debug data summary
    IO.puts("\n------ KILLMAIL DEBUG DATA SUMMARY ------")
    debug_data = debug_killmail_data(killmail_data)

    Enum.each(debug_data, fn {key, value} ->
      if is_map(value) || is_list(value) do
        IO.puts("#{key}: #{inspect(value, limit: 50)}")
      else
        IO.puts("#{key}: #{value}")
      end
    end)

    # Check if force notification is enabled
    if Application.get_env(:wanderer_notifier, :force_notify_next_killmail) do
      force_notify_killmail(killmail_data)
      # Reset the notification flag
      Application.put_env(:wanderer_notifier, :force_notify_next_killmail, false)
    end

    # Don't reset the log flag here - let the enrichment step also use it
    # The flag will be reset after enrichment logging is complete

    :ok
  end

  @doc """
  Force a notification for a specific killmail, bypassing normal tracking criteria.
  This is useful for testing notification templates and delivery.

  ## Parameters
  - killmail: The killmail data structure to process for notification

  ## Returns
  - :ok when notification processing has been triggered
  """
  def force_notify_killmail(killmail) do
    IO.puts("\n------ FORCING NOTIFICATION PROCESSING ------")
    IO.puts("🔔 Processing notification regardless of tracking status...")

    # Create a debug context that forces notification
    ctx = Context.new_realtime(nil, nil, :debug_force_notify, %{force_notification: true})

    # Process through the pipeline with forced notification
    case KillmailProcessor.process_killmail(killmail, ctx) do
      {:ok, result} ->
        IO.puts("✅ Notification processing completed successfully: #{inspect(result)}")
        :ok

      {:error, reason} ->
        IO.puts("❌ Notification processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Force a notification for a specific killmail ID by fetching it from zKillboard,
  bypassing normal tracking criteria.

  ## Parameters
  - killmail_id: The killmail ID to fetch and process for notification

  ## Returns
  - :ok when notification processing has been triggered
  - {:error, reason} when an error occurs
  """
  def force_notify_killmail_by_id(killmail_id)
      when is_integer(killmail_id) or is_binary(killmail_id) do
    # Convert to integer if string
    kill_id = if is_binary(killmail_id), do: String.to_integer(killmail_id), else: killmail_id

    IO.puts("\n------ FORCING NOTIFICATION FOR KILLMAIL #{kill_id} ------")
    IO.puts("🔍 Fetching killmail data from zKillboard...")

    # Create a temporary tracking context for this killmail
    # We're faking a tracked character to ensure the killmail gets processed
    case Core.process_kill_from_zkb(kill_id, nil) do
      {:ok, _} = result ->
        IO.puts("✅ Notification processing triggered successfully!")
        result

      error ->
        IO.puts("❌ Failed to process killmail: #{inspect(error)}")
        error
    end
  end

  # Extract the killmail ID from different possible formats
  defp extract_killmail_id(json_data) do
    cond do
      Map.has_key?(json_data, "killmail_id") ->
        json_data["killmail_id"]

      Map.has_key?(json_data, "zkb") && Map.has_key?(json_data["zkb"], "killmail_id") ->
        json_data["zkb"]["killmail_id"]

      true ->
        "unknown"
    end
  end

  # Helper function to create a debug data summary
  defp debug_killmail_data(killmail) do
    %{
      # Basic fields
      killmail_id: killmail.killmail_id,

      # ESI fields (if present)
      solar_system_id: get_from_esi_data(killmail, "solar_system_id"),
      solar_system_name: killmail.solar_system_name,
      region_id: get_region_id(killmail),
      region_name: get_region_name(killmail),
      killmail_time: killmail.kill_time,

      # Victim and attacker data
      victim: get_from_esi_data(killmail, "victim"),
      attackers_count: if(is_list(killmail.attackers), do: length(killmail.attackers), else: 0),

      # ZKB data
      zkb_total_value: get_zkb_value(killmail),

      # Extra info
      has_esi_data: has_esi_data?(killmail),
      esi_data_keys: if(has_esi_data?(killmail), do: Map.keys(killmail.raw_esi_data), else: []),
      zkb_keys: if(has_zkb_data?(killmail), do: Map.keys(get_zkb_data(killmail)), else: [])
    }
  end

  # Helper function to get data from raw_esi_data or direct field
  defp get_from_esi_data(killmail, key) do
    if is_map(killmail.raw_esi_data) do
      Map.get(killmail.raw_esi_data, key)
    else
      nil
    end
  end

  # Helper functions for accessing data in either format
  defp get_region_id(killmail) do
    killmail.region_id ||
      (is_map(killmail.raw_esi_data) && Map.get(killmail.raw_esi_data, "region_id"))
  end

  defp get_region_name(killmail) do
    killmail.region_name ||
      (is_map(killmail.raw_esi_data) && Map.get(killmail.raw_esi_data, "region_name"))
  end

  defp get_zkb_value(killmail) do
    if has_zkb_data?(killmail) do
      zkb_data = get_zkb_data(killmail)
      Map.get(zkb_data, "totalValue") || Map.get(zkb_data, "total_value")
    else
      nil
    end
  end

  defp get_zkb_data(killmail) do
    killmail.raw_zkb_data || killmail.zkb || %{}
  end

  defp has_esi_data?(killmail) do
    is_map(killmail.raw_esi_data) && killmail.raw_esi_data != %{}
  end

  defp has_zkb_data?(killmail) do
    (is_map(killmail.raw_zkb_data) && killmail.raw_zkb_data != %{}) ||
      (is_map(killmail.zkb) && killmail.zkb != %{})
  end
end
