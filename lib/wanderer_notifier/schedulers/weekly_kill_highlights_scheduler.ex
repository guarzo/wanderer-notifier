defmodule WandererNotifier.Schedulers.WeeklyKillHighlightsScheduler do
  @moduledoc """
  Scheduler for sending weekly kill highlights to Discord.
  Sends the best kill and worst loss from the past week for tracked characters.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Api.ESI.Service, as: ESIService

  require Ash.Query, as: Query

  @impl true
  def enabled? do
    Features.kill_charts_enabled?()
  end

  @impl true
  def execute(state) do
    if enabled?() do
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Sending weekly kill highlights to Discord"
      )

      # Get the Discord channel ID for kill highlights
      channel_id = NotificationConfig.discord_channel_id_for(:kill_charts)

      case process_weekly_highlights(channel_id) do
        {:ok, _} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Successfully sent kill highlights")
          {:ok, :completed, state}

        {:error, :feature_disabled} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Kill highlights feature disabled")
          {:ok, :skipped, Map.put(state, :reason, :feature_disabled)}

        {:error, reason} ->
          AppLogger.scheduler_error("#{inspect(__MODULE__)}: Failed to send kill highlights",
            error: inspect(reason)
          )

          {:error, reason, state}
      end
    else
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Skipping weekly kill highlights (disabled)"
      )

      {:ok, :skipped, Map.put(state, :reason, :scheduler_disabled)}
    end
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.weekly_kill_data_fetch_interval(),
      description: "Weekly kill highlights Discord sending"
    }
  end

  @impl true
  def send_test_highlights do
    AppLogger.scheduler_info("Sending test weekly kill highlights")

    # Get channel ID from config
    channel_id = config().discord_channel_id_for(:kill_charts)

    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for test kill charts")
      {:error, "No channel ID configured"}
    else
      # Calculate date range for the past week
      now = DateTime.utc_now()
      # Use 7 days for testing
      days_ago = DateTime.add(now, -7 * 86_400, :second)

      # Log the query date range
      AppLogger.scheduler_info(
        "Test kill highlights using date range: #{DateTime.to_string(days_ago)} to #{DateTime.to_string(now)}"
      )

      # Log total kills and losses in database for test diagnostics
      # Use simple queries instead of aggregation
      all_kills_query =
        Killmail
        |> Query.filter(character_role == :attacker)
        |> Query.limit(1000)

      all_losses_query =
        Killmail
        |> Query.filter(character_role == :victim)
        |> Query.limit(1000)

      # Check total database counts for diagnostics
      all_kills_result = Api.read(all_kills_query)
      all_losses_result = Api.read(all_losses_query)

      case {all_kills_result, all_losses_result} do
        {{:ok, kills}, {:ok, losses}} ->
          kills_count = length(kills)
          losses_count = length(losses)

          AppLogger.scheduler_info(
            "Database diagnostics: Sampled kills: #{kills_count}, Sampled losses: #{losses_count} (limited to 1000 each)"
          )

        _ ->
          AppLogger.scheduler_error("Unable to count kills and losses in database")
      end

      # Run the regular weekly highlights processing with standard date range
      try do
        case process_weekly_highlights_with_date_range(channel_id, days_ago, now) do
          {:ok, _} = result ->
            AppLogger.scheduler_info("Successfully sent test kill highlights")
            result

          {:error, reason} = error ->
            AppLogger.scheduler_error("Failed to send test kill charts: #{inspect(reason)}")
            error
        end
      rescue
        e ->
          AppLogger.scheduler_error("Exception sending test kill charts: #{Exception.message(e)}")

          {:error, "Exception: #{Exception.message(e)}"}
      end
    end
  end

  # Process the weekly kill highlights for a specific date range
  defp process_weekly_highlights_with_date_range(channel_id, start_date, end_date) do
    if is_nil(channel_id) do
      AppLogger.scheduler_error("No channel ID configured for kill charts")
      {:error, "No channel ID configured"}
    else
      # Format date range for display
      start_str = Calendar.strftime(start_date, "%Y-%m-%d")
      end_str = Calendar.strftime(end_date, "%Y-%m-%d")
      date_range = "#{start_str} to #{end_str}"

      AppLogger.scheduler_info("Processing kill highlights for period: #{date_range}")

      # Track if we successfully sent anything
      kills_sent = 0

      # Get best kill - process independently
      best_kill_result = find_best_kill(start_date, end_date)

      kills_sent =
        case best_kill_result do
          {:ok, kill} ->
            AppLogger.scheduler_info("Sending best kill notification")
            # Format the Discord embed with the killmail data
            kill_embed = format_kill_embed(kill, true, date_range)
            NotifierFactory.notify(:send_discord_embed_to_channel, [channel_id, kill_embed])
            1

          {:error, reason} ->
            AppLogger.scheduler_warn("Unable to send best kill notification: #{inspect(reason)}")
            0
        end

      # Get worst loss - process independently
      worst_loss_result = find_worst_loss(start_date, end_date)

      losses_sent =
        case worst_loss_result do
          {:ok, loss} ->
            AppLogger.scheduler_info("Sending worst loss notification")
            # Format the Discord embed with the killmail data
            loss_embed = format_kill_embed(loss, false, date_range)
            NotifierFactory.notify(:send_discord_embed_to_channel, [channel_id, loss_embed])
            1

          {:error, reason} ->
            AppLogger.scheduler_warn("Unable to send worst loss notification: #{inspect(reason)}")

            0
        end

      total_sent = kills_sent + losses_sent

      # Return overall result
      if total_sent > 0 do
        # At least one notification was sent
        AppLogger.scheduler_info("Successfully sent #{total_sent} kill highlight notifications")
        {:ok, :sent}
      else
        # Nothing was sent
        AppLogger.scheduler_error("Failed to send any kill highlights")
        {:error, :no_kills}
      end
    end
  rescue
    e ->
      AppLogger.scheduler_error("Error processing kill highlights",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Exception: #{Exception.message(e)}"}
  end

  # Process the weekly kill highlights
  defp process_weekly_highlights(channel_id) do
    # Calculate date range for the past week
    now = DateTime.utc_now()
    week_ago = DateTime.add(now, -7 * 86_400, :second)

    # Use the generic function with the weekly date range
    process_weekly_highlights_with_date_range(channel_id, week_ago, now)
  end

  # Find the best kill (highest value) in the given period
  defp find_best_kill(start_date, end_date) do
    # Log query parameters
    AppLogger.scheduler_info(
      "Searching for best kill between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    # Get kills in the date range
    date_query =
      Killmail
      |> Query.filter(character_role == :attacker)
      |> Query.filter(kill_time >= ^start_date)
      |> Query.filter(kill_time <= ^end_date)
      |> Query.sort(total_value: :desc)
      |> Query.limit(50)

    case Api.read(date_query) do
      {:ok, []} ->
        AppLogger.scheduler_warn("No kills found in the date range")
        {:error, :no_kills_in_range}

      {:ok, kills} ->
        # Log all the found kills for debugging
        kills_count = length(kills)
        AppLogger.scheduler_info("Found #{kills_count} kills in date range")

        # Filter for kills with value
        kills_with_value = Enum.filter(kills, fn kill -> kill.total_value != nil end)

        if kills_with_value != [] do
          # Get the kill with the highest value (should already be sorted, but just to be safe)
          best_kill =
            Enum.max_by(
              kills_with_value,
              fn kill ->
                case kill.total_value do
                  nil -> Decimal.new(0)
                  val when is_struct(val, Decimal) -> val
                  _ -> Decimal.new(0)
                end
              end
            )

          # Log the complete killmail struct for debugging
          AppLogger.scheduler_info(
            "FULL BEST KILLMAIL STRUCT: #{inspect(best_kill, pretty: true, limit: :infinity)}"
          )

          # Enrich missing data if necessary
          best_kill = enrich_killmail_data(best_kill)

          # Log selected kill details for debugging
          AppLogger.scheduler_info(
            "Selected best kill: ID=#{best_kill.killmail_id}, " <>
              "Character=#{best_kill.related_character_name || "Unknown"}, " <>
              "Ship=#{best_kill.ship_type_name || "Unknown"}, " <>
              "System=#{best_kill.solar_system_name || "Unknown"}, " <>
              "Region=#{best_kill.region_name || "Unknown"}, " <>
              "Value=#{inspect(best_kill.total_value)}, " <>
              "Time=#{DateTime.to_string(best_kill.kill_time)}"
          )

          {:ok, best_kill}
        else
          AppLogger.scheduler_warn("No kills with valid values found")
          {:error, :no_kills_with_value}
        end

      error ->
        AppLogger.scheduler_error("Error querying kills in date range: #{inspect(error)}")
        {:error, "Failed to find kills in date range"}
    end
  end

  # Find the worst loss (highest value) in the given period
  defp find_worst_loss(start_date, end_date) do
    # Log query parameters
    AppLogger.scheduler_info(
      "Searching for worst loss between #{DateTime.to_string(start_date)} and #{DateTime.to_string(end_date)}"
    )

    # Get losses in the date range
    date_query =
      Killmail
      |> Query.filter(character_role == :victim)
      |> Query.filter(kill_time >= ^start_date)
      |> Query.filter(kill_time <= ^end_date)
      |> Query.sort(total_value: :desc)
      |> Query.limit(50)

    case Api.read(date_query) do
      {:ok, []} ->
        AppLogger.scheduler_warn("No losses found in the date range")
        {:error, :no_losses_in_range}

      {:ok, losses} ->
        # Log all the found losses for debugging
        losses_count = length(losses)
        AppLogger.scheduler_info("Found #{losses_count} losses in date range")

        # Filter for losses with value
        losses_with_value = Enum.filter(losses, fn loss -> loss.total_value != nil end)

        if losses_with_value != [] do
          # Get the loss with the highest value (should already be sorted, but just to be safe)
          worst_loss =
            Enum.max_by(
              losses_with_value,
              fn loss ->
                case loss.total_value do
                  nil -> Decimal.new(0)
                  val when is_struct(val, Decimal) -> val
                  _ -> Decimal.new(0)
                end
              end
            )

          # Enrich missing data if necessary
          worst_loss = enrich_killmail_data(worst_loss)

          # Log selected loss details for debugging
          AppLogger.scheduler_info(
            "Selected worst loss: ID=#{worst_loss.killmail_id}, " <>
              "Character=#{worst_loss.related_character_name || "Unknown"}, " <>
              "Ship=#{worst_loss.ship_type_name || "Unknown"}, " <>
              "System=#{worst_loss.solar_system_name || "Unknown"}, " <>
              "Region=#{worst_loss.region_name || "Unknown"}, " <>
              "Value=#{inspect(worst_loss.total_value)}, " <>
              "Time=#{DateTime.to_string(worst_loss.kill_time)}"
          )

          {:ok, worst_loss}
        else
          AppLogger.scheduler_warn("No losses with valid values found")
          {:error, :no_losses_with_value}
        end

      error ->
        AppLogger.scheduler_error("Error querying losses in date range: #{inspect(error)}")
        {:error, "Failed to find losses in date range"}
    end
  end

  # Enrich killmail with missing system and region data
  defp enrich_killmail_data(killmail) do
    # Log the current values
    AppLogger.scheduler_info(
      "Enriching killmail: ID=#{killmail.killmail_id}, " <>
        "Character=#{killmail.related_character_name || "Unknown"}, " <>
        "Ship=#{killmail.ship_type_name || "Unknown"}, " <>
        "System=#{killmail.solar_system_name || "Unknown"}, " <>
        "System ID=#{killmail.solar_system_id || "nil"}"
    )

    # Try to get character name if it's missing
    killmail =
      if is_nil(killmail.related_character_name) ||
           killmail.related_character_name == "Unknown Character" do
        # If this is a kill, try to get from victim_data
        if killmail.character_role == :attacker && not is_nil(killmail.victim_data) do
          char_name = get_in(killmail.victim_data, ["character_name"])

          if not is_nil(char_name) && char_name != "" do
            AppLogger.scheduler_info("Using character name from victim data: #{char_name}")
            %{killmail | related_character_name: char_name}
          else
            # Try attacker data
            if not is_nil(killmail.attacker_data) do
              char_name = get_in(killmail.attacker_data, ["character_name"])

              if not is_nil(char_name) && char_name != "" do
                AppLogger.scheduler_info("Using character name from attacker data: #{char_name}")
                %{killmail | related_character_name: char_name}
              else
                AppLogger.scheduler_info("No character name found in kill data")
                # Use "Unknown Pilot" instead of "Unknown Character" for consistency
                %{killmail | related_character_name: "Unknown Pilot"}
              end
            else
              # Use "Unknown Pilot" instead of "Unknown Character" for consistency
              %{killmail | related_character_name: "Unknown Pilot"}
            end
          end
        else
          # For losses
          if killmail.character_role == :victim && not is_nil(killmail.victim_data) do
            char_name = get_in(killmail.victim_data, ["character_name"])

            if not is_nil(char_name) && char_name != "" do
              AppLogger.scheduler_info("Using character name from victim data: #{char_name}")
              %{killmail | related_character_name: char_name}
            else
              AppLogger.scheduler_info("No character name found in loss data")
              # Use "Unknown Pilot" instead of "Unknown Character" for consistency
              %{killmail | related_character_name: "Unknown Pilot"}
            end
          else
            # Use "Unknown Pilot" instead of "Unknown Character" for consistency
            %{killmail | related_character_name: "Unknown Pilot"}
          end
        end
      else
        killmail
      end

    # Try to fix ship name if it's missing (for losses)
    killmail =
      if (is_nil(killmail.ship_type_name) || killmail.ship_type_name == "Unknown Ship") &&
           killmail.character_role == :victim &&
           not is_nil(killmail.victim_data) do
        ship_name = get_in(killmail.victim_data, ["ship_type_name"])

        if not is_nil(ship_name) && ship_name != "" do
          AppLogger.scheduler_info("Using ship name from victim data: #{ship_name}")
          %{killmail | ship_type_name: ship_name}
        else
          killmail
        end
      else
        killmail
      end

    # Try to fix system name if missing
    if (is_nil(killmail.solar_system_name) || killmail.solar_system_name == "Unknown System") &&
         not is_nil(killmail.solar_system_id) do
      # For system ID, use J-format for wormhole systems
      if is_integer(killmail.solar_system_id) do
        system_id_str = "J#{killmail.solar_system_id}"
        AppLogger.scheduler_info("Using J-format system name: #{system_id_str}")
        %{killmail | solar_system_name: system_id_str}
      else
        killmail
      end
    else
      killmail
    end
  end

  # Format a kill/loss into a Discord embed
  defp format_kill_embed(killmail, is_kill, date_range) do
    # See if solar_system_name is already in J-format
    system_name =
      if is_nil(killmail.solar_system_name) || killmail.solar_system_name == "Unknown System" do
        # Try to construct from system ID if available (common for wormhole systems)
        if is_integer(killmail.solar_system_id) do
          "J#{killmail.solar_system_id}"
        else
          "Unknown System"
        end
      else
        killmail.solar_system_name
      end

    # For system names starting with J and no region, it's a wormhole system
    region_name =
      if system_name != nil &&
           String.starts_with?(system_name, "J") &&
           (killmail.region_name == nil || killmail.region_name == "Unknown Region") do
        "J-Space"
      else
        killmail.region_name || "Unknown Region"
      end

    # Try to get character name from victim_data for losses
    character_name =
      if not is_kill &&
           (killmail.related_character_name == nil ||
              killmail.related_character_name == "Unknown Character") do
        if not is_nil(killmail.victim_data) do
          get_in(killmail.victim_data, ["character_name"]) || "Unknown Pilot"
        else
          "Unknown Pilot"
        end
      else
        killmail.related_character_name || "Unknown Pilot"
      end

    # Try to get ship name from victim_data for losses
    ship_name =
      if not is_kill &&
           (killmail.ship_type_name == nil || killmail.ship_type_name == "Unknown Ship") do
        if not is_nil(killmail.victim_data) do
          get_in(killmail.victim_data, ["ship_type_name"]) || "Unknown Ship"
        else
          "Unknown Ship"
        end
      else
        killmail.ship_type_name || "Unknown Ship"
      end

    ship_type_id = killmail.ship_type_id

    # Log the full killmail for debugging
    AppLogger.scheduler_info(
      "Formatting #{if is_kill, do: "kill", else: "loss"} embed: " <>
        "ID=#{killmail.killmail_id}, " <>
        "Character=#{character_name}, " <>
        "Ship=#{ship_name} (ID=#{ship_type_id}), " <>
        "System=#{system_name}, " <>
        "Region=#{region_name}, " <>
        "Value=#{inspect(killmail.total_value)}"
    )

    # Format ISK value
    formatted_isk = format_isk(killmail.total_value)

    # Determine title, description and color based on whether this is a kill or loss
    {title, description, color} =
      if is_kill do
        {
          "🏆 Best Kill of the Week",
          "#{character_name} scored our most valuable kill this week!",
          # Green
          0x00FF00
        }
      else
        {
          "💀 Worst Loss of the Week",
          "#{character_name} suffered our most expensive loss this week.",
          # Red
          0xFF0000
        }
      end

    # Victim info (for kills)
    victim_info =
      if is_kill && killmail.victim_data do
        victim_ship = get_in(killmail.victim_data, ["ship_type_name"]) || "Unknown Ship"
        victim_corp = get_in(killmail.victim_data, ["corporation_name"]) || "Unknown Corporation"
        "Destroyed a #{victim_ship} belonging to #{victim_corp}"
      else
        nil
      end

    # Build the embed
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color,
      "fields" => [
        %{
          "name" => "Value",
          "value" => formatted_isk,
          "inline" => true
        },
        %{
          "name" => "Ship",
          "value" => ship_name,
          "inline" => true
        },
        %{
          "name" => "Location",
          "value" => "#{system_name} (#{region_name})",
          "inline" => true
        }
      ],
      "footer" => %{
        "text" => "Week of #{date_range}"
      },
      "timestamp" => DateTime.to_iso8601(killmail.kill_time)
    }

    # Add victim info field if available
    embed =
      if victim_info do
        updated_fields =
          embed["fields"] ++
            [
              %{
                "name" => "Details",
                "value" => victim_info,
                "inline" => false
              }
            ]

        %{embed | "fields" => updated_fields}
      else
        embed
      end

    # Add thumbnail if possible
    embed =
      if is_kill do
        # For kills, try to use victim ship image
        victim_type_id = get_in(killmail.victim_data, ["ship_type_id"])

        if victim_type_id do
          ship_image_url = "https://images.evetech.net/types/#{victim_type_id}/render?size=128"
          Map.put(embed, "thumbnail", %{"url" => ship_image_url})
        else
          embed
        end
      else
        # For losses, use our ship image
        if ship_type_id do
          ship_image_url =
            "https://images.evetech.net/types/#{ship_type_id}/render?size=128"

          Map.put(embed, "thumbnail", %{"url" => ship_image_url})
        else
          embed
        end
      end

    # Log the generated embed
    AppLogger.scheduler_info(
      "Generated embed for #{if is_kill, do: "kill", else: "loss"}: " <>
        "Title=\"#{embed["title"]}\", " <>
        "Character=#{character_name}, " <>
        "Ship=#{ship_name}, " <>
        "System=#{system_name}, " <>
        "Region=#{region_name}, " <>
        "Fields=#{length(embed["fields"])}, " <>
        "Has thumbnail=#{Map.has_key?(embed, "thumbnail")}"
    )

    embed
  end

  # Format ISK value for display
  defp format_isk(value) do
    # Log the raw value
    AppLogger.scheduler_info("Formatting ISK value: Raw value = #{inspect(value)}")

    # Handle nil value
    if is_nil(value) do
      "Unknown"
    else
      # Try to convert to float
      float_value = try_convert_to_float(value)

      # Log the converted float value
      AppLogger.scheduler_info("Converted value to float: #{float_value}")

      # Format based on magnitude
      cond do
        float_value >= 1_000_000_000 ->
          "#{format_float(float_value / 1_000_000_000)} billion ISK"

        float_value >= 1_000_000 ->
          "#{format_float(float_value / 1_000_000)} million ISK"

        float_value >= 1_000 ->
          "#{format_float(float_value / 1_000)} thousand ISK"

        true ->
          "#{format_float(float_value)} ISK"
      end
    end
  end

  # Helper function to try converting a value to float
  defp try_convert_to_float(value) do
    try do
      cond do
        # Already a float
        is_float(value) ->
          value

        # Integer -> float
        is_integer(value) ->
          value / 1.0

        # String -> float
        is_binary(value) ->
          case Float.parse(value) do
            {float, _} -> float
            :error -> 0.0
          end

        # Decimal -> float
        is_map(value) && Map.has_key?(value, :__struct__) && value.__struct__ == Decimal ->
          try do
            # Try Decimal.to_float
            Decimal.to_float(value)
          rescue
            # If that fails, try string conversion
            _ ->
              try do
                str = Decimal.to_string(value)

                case Float.parse(str) do
                  {float, _} -> float
                  :error -> 0.0
                end
              rescue
                # Last resort
                _ -> 0.0
              end
          end

        # Any other struct with a :value field (some composite types)
        is_map(value) && Map.has_key?(value, :__struct__) && Map.has_key?(value, :value) ->
          try_convert_to_float(Map.get(value, :value))

        # Any other map with a "value" key (JSON data)
        is_map(value) && Map.has_key?(value, "value") ->
          try_convert_to_float(Map.get(value, "value"))

        # Default case
        true ->
          0.0
      end
    rescue
      # Catch any unexpected errors
      error ->
        AppLogger.scheduler_error("Error converting value to float: #{inspect(error)}")
        0.0
    end
  end

  # Helper to format a float to 2 decimal places
  defp format_float(float) do
    :erlang.float_to_binary(float, [{:decimals, 2}])
  end

  # Helper function to check if a value is a valid integer
  defp valid_integer?(value) when is_integer(value), do: true
  defp valid_integer?(_), do: false

  # For dependency injection in tests
  defp config do
    Application.get_env(:wanderer_notifier, :config_module, NotificationConfig)
  end

  @impl true
  def health_check do
    # Get channel ID from config
    channel_id = config().discord_channel_id_for(:kill_charts)

    if is_nil(channel_id) do
      {:error, "No Discord channel configured for kill charts"}
    else
      {:ok, %{channel_id: channel_id}}
    end
  end
end
