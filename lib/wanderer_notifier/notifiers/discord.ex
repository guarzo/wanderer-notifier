defmodule WandererNotifier.Notifiers.Discord do
  @moduledoc """
  Discord notifier for WandererNotifier.
  Handles formatting and sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Core.License
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Notifiers.Formatter

  @behaviour WandererNotifier.Notifiers.Behaviour

  # Default embed color
  @default_embed_color 0x3498DB

  @base_url "https://discord.com/api/channels"
  # Set to true to enable verbose logging
  @verbose_logging false

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  # Use runtime configuration so tests can override it
  defp env, do: Application.get_env(:wanderer_notifier, :env, :prod)

  defp get_config!(key, error_msg) do
    environment = env()

    case Application.get_env(:wanderer_notifier, key) do
      nil when environment != :test -> raise error_msg
      "" when environment != :test -> raise error_msg
      value -> value
    end
  end

  # Helper function to handle test mode logging and response
  defp handle_test_mode(log_message) do
    if @verbose_logging, do: Logger.info(log_message)
    :ok
  end

  defp channel_id_for_feature(feature) do
    Config.discord_channel_id_for(feature)
  end

  defp bot_token,
    do:
    
      get_config!(
        :discord_bot_token,
        "Discord bot token not configured. Please set :discord_bot_token in your configuration."
      )

  defp build_url(feature) do
    channel = channel_id_for_feature(feature)
    "#{@base_url}/#{channel}/messages"
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{bot_token()}"}
    ]
  end

  # -- HELPER FUNCTIONS --

  # Retrieves a value from a map checking both string and atom keys.
  # Tries each key in the provided list until a value is found.
  @spec get_value(map(), [String.t()], any()) :: any()
  defp get_value(map, keys, default) do
    Enum.find_value(keys, default, fn key ->
      Map.get(map, key) || Map.get(map, String.to_atom(key))
    end)
  end

  # -- MESSAGE SENDING --

  @doc """
  Sends a plain text message to Discord.

  ## Parameters
    - message: The message to send
    - feature: Optional feature to determine the channel to use (defaults to :general)
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_message(message, feature \\ :general) when is_binary(message) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{message}")
    else
      payload =
        if String.contains?(message, "test kill notification") do
          process_test_kill_notification(message)
        else
          %{"content" => message, "embeds" => []}
        end

      send_payload(payload, feature)
    end
  end

  defp process_test_kill_notification(message) do
    recent_kills = WandererNotifier.Services.KillProcessor.get_recent_kills() || []

    if recent_kills != [] do
      recent_kill = List.first(recent_kills)
      kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

      if kill_id,
        do: send_enriched_kill_embed(recent_kill, kill_id),
        else: %{"content" => message, "embeds" => []}
    else
      %{"content" => message, "embeds" => []}
    end
  end

  @spec send_embed(any(), any(), any(), any(), atom()) :: :ok | {:error, any()}
  @doc """
  Sends a basic embed message to Discord.

  ## Parameters
    - title: The embed title
    - description: The embed description
    - url: Optional URL for the embed
    - color: Optional color for the embed
    - feature: Optional feature to determine the channel to use
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color, feature \\ :general) do
    Logger.info("Discord.Notifier.send_embed called with title: #{title}, url: #{url || "nil"}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED: #{title} - #{description}")
    else
      payload =
        if title == "Test Kill" do
          process_test_embed(title, description, url, color)
        else
          build_embed_payload(title, description, url, color)
        end

      Logger.info("Discord embed payload built, sending to Discord API")
      send_payload(payload, feature)
    end
  end

  defp process_test_embed(title, description, url, color) do
    recent_kills = WandererNotifier.Services.KillProcessor.get_recent_kills() || []

    if recent_kills != [] do
      recent_kill = List.first(recent_kills)
      kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

      if kill_id,
        do: send_enriched_kill_embed(recent_kill, kill_id),
        else: build_embed_payload(title, description, url, color)
    else
      build_embed_payload(title, description, url, color)
    end
  end

  defp build_embed_payload(title, description, url, color) do
    embed =
      %{
        "title" => title,
        "description" => description,
        "color" => color
      }
      |> maybe_put("url", url)

    %{"embeds" => [embed]}
  end

  # Inserts a key only if the value is not nil.
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Sends a Discord embed using the Discord API.

  ## Parameters
    - embed: The embed to send
    - feature: The feature to use for determining the channel (optional)
  """
  def send_discord_embed(embed, feature \\ :general) do
    url = build_url(feature)
    Logger.info("Sending Discord embed to URL: #{url} for feature: #{inspect(feature)}")
    Logger.debug("Embed content: #{inspect(embed)}")

    payload = %{"embeds" => [embed]}

    with {:ok, json} <- Jason.encode(payload),
         {:ok, %{status_code: status}} when status in 200..299 <-
           HttpClient.request("POST", url, headers(), json) do
      Logger.info("Successfully sent Discord embed, status: #{status}")
      :ok
    else
      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to send Discord embed: status=#{status}, body=#{inspect(body)}")
        {:error, "Discord API error: #{status}"}

      {:error, reason} ->
        Logger.error("Error sending Discord embed: #{inspect(reason)}")
        {:error, reason}

      error ->
        Logger.error("Unexpected error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  Expects the enriched killmail (and its nested maps) to have string keys.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    if env() == :test do
      handle_test_mode("TEST MODE: Would send enriched kill embed for kill_id=#{kill_id}")
    else
      enriched_kill = fully_enrich_kill_data(enriched_kill)
      victim = Map.get(enriched_kill, "victim") || %{}
      victim_name = get_value(victim, ["character_name"], "Unknown Pilot")
      victim_ship = get_value(victim, ["ship_type_name"], "Unknown Ship")
      system_name = Map.get(enriched_kill, "solar_system_name") || "Unknown System"

      if License.status().valid do
        # Use the formatter to create the notification
        generic_notification = Formatter.format_kill_notification(enriched_kill, kill_id)
        discord_embed = Formatter.to_discord_format(generic_notification)
        send_discord_embed(discord_embed, :kill_notifications)
      else
        Logger.info(
          "License not valid, sending plain text kill notification instead of rich embed"
        )

        send_message("Kill Alert: #{victim_name} lost a #{victim_ship} in #{system_name}.")
      end
    end
  end

  # -- ENRICHMENT FUNCTIONS --

  defp fully_enrich_kill_data(enriched_kill) do
    Logger.debug("Processing kill data: #{inspect(enriched_kill, pretty: true)}")

    victim =
      enriched_kill
      |> Map.get("victim", %{})
      |> enrich_victim_data()

    attackers =
      enriched_kill
      |> Map.get("attackers", [])
      |> Enum.map(&enrich_attacker_data/1)

    enriched_kill
    |> Map.put("victim", victim)
    |> Map.put("attackers", attackers)
  end

  defp enrich_victim_data(victim) do
    victim =
      case get_value(victim, ["character_name"], nil) do
        nil ->
          victim
          |> enrich_character("character_id", fn character_id ->
            case ESIService.get_character_info(character_id) do
              {:ok, char_data} ->
                Map.put(victim, "character_name", Map.get(char_data, "name", "Unknown Pilot"))
                |> enrich_corporation("corporation_id", char_data)

              _ ->
                Map.put_new(victim, "character_name", "Unknown Pilot")
            end
          end)

        _ ->
          victim
      end

    victim =
      case get_value(victim, ["ship_type_name"], nil) do
        nil ->
          victim
          |> enrich_character("ship_type_id", fn ship_type_id ->
            case ESIService.get_ship_type_name(ship_type_id) do
              {:ok, ship_data} ->
                Map.put(victim, "ship_type_name", Map.get(ship_data, "name", "Unknown Ship"))

              _ ->
                Map.put_new(victim, "ship_type_name", "Unknown Ship")
            end
          end)

        _ ->
          victim
      end

    if get_value(victim, ["corporation_name"], "Unknown Corp") == "Unknown Corp" do
      victim =
        enrich_character(victim, "character_id", fn character_id ->
          case ESIService.get_character_info(character_id) do
            {:ok, char_data} ->
              case Map.get(char_data, "corporation_id") do
                nil ->
                  victim

                corp_id ->
                  case ESIService.get_corporation_info(corp_id) do
                    {:ok, corp_data} ->
                      Map.put(
                        victim,
                        "corporation_name",
                        Map.get(corp_data, "name", "Unknown Corp")
                      )

                    _ ->
                      Map.put_new(victim, "corporation_name", "Unknown Corp")
                  end
              end

            _ ->
              victim
          end
        end)

      victim
    else
      victim
    end
  end

  defp enrich_character(data, key, fun) do
    case Map.get(data, key) || Map.get(data, String.to_atom(key)) do
      nil -> data
      value -> fun.(value)
    end
  end

  defp enrich_corporation(victim, _key, char_data) do
    case Map.get(victim, "corporation_id") || Map.get(victim, :corporation_id) ||
           Map.get(char_data, "corporation_id") do
      nil ->
        victim

      corp_id ->
        case ESIService.get_corporation_info(corp_id) do
          {:ok, corp_data} ->
            Map.put(victim, "corporation_name", Map.get(corp_data, "name", "Unknown Corp"))

          _ ->
            Map.put_new(victim, "corporation_name", "Unknown Corp")
        end
    end
  end

  defp enrich_attacker_data(attacker) do
    attacker =
      case get_value(attacker, ["character_name"], nil) do
        nil ->
          enrich_character(attacker, "character_id", fn character_id ->
            case ESIService.get_character_info(character_id) do
              {:ok, char_data} ->
                Map.put(attacker, "character_name", Map.get(char_data, "name", "Unknown Pilot"))

              _ ->
                Map.put_new(attacker, "character_name", "Unknown Pilot")
            end
          end)

        _ ->
          attacker
      end

    case get_value(attacker, ["ship_type_name"], nil) do
      nil ->
        enrich_character(attacker, "ship_type_id", fn ship_type_id ->
          case ESIService.get_ship_type_name(ship_type_id) do
            {:ok, ship_data} ->
              Map.put(attacker, "ship_type_name", Map.get(ship_data, "name", "Unknown Ship"))

            _ ->
              Map.put_new(attacker, "ship_type_name", "Unknown Ship")
          end
        end)

      _ ->
        attacker
    end
  end

  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{round(value / 1000)}k ISK"
      true -> "#{round(value / 1_000_000)}M ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

  # -- NEW TRACKED CHARACTER NOTIFICATION --

  @doc """
  Sends a notification for a new tracked character.
  Expects a map with keys: "character_id", "character_name", "corporation_id", "corporation_name".
  If names are missing, ESI lookups are performed.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_tracked_character_notification(character) when is_map(character) do
    if env() == :test do
      character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
      handle_test_mode("DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
    else
      try do
        Stats.increment(:characters)
      rescue
        _ -> :ok
      end

      # Enrich the character data with ESI lookups if needed
      character = enrich_character_data(character)

      if License.status().valid do
        # Use the formatter module to create the notification
        generic_notification = Formatter.format_character_notification(character)
        discord_embed = Formatter.to_discord_format(generic_notification)
        send_discord_embed(discord_embed, :character_tracking)
      else
        Logger.info("License not valid, sending plain text character notification")
        character_name = get_value(character, ["character_name"], "Unknown Character")
        corporation_name = get_value(character, ["corporation_name"], nil)

        message =
          "New Character Tracked: #{character_name}" <>
            if corporation_name, do: " (#{corporation_name})", else: ""

        send_message(message)
      end
    end
  end

  defp enrich_character_data(character) do
    character =
      case get_value(character, ["character_name"], nil) do
        nil ->
          enrich_character(character, "character_id", fn character_id ->
            case ESIService.get_character_info(character_id) do
              {:ok, char_data} ->
                Map.put(character, "character_name", Map.get(char_data, "name", "Unknown Pilot"))

              _ ->
                Map.put_new(character, "character_name", "Unknown Pilot")
            end
          end)

        _ ->
          character
      end

    character =
      case get_value(character, ["corporation_name"], nil) do
        nil ->
          case Map.get(character, "corporation_id") || Map.get(character, :corporation_id) do
            nil ->
              Map.put_new(character, "corporation_name", "Unknown Corp")

            corp_id ->
              case ESIService.get_corporation_info(corp_id) do
                {:ok, corp_data} ->
                  Map.put(
                    character,
                    "corporation_name",
                    Map.get(corp_data, "name", "Unknown Corp")
                  )

                _ ->
                  Map.put_new(character, "corporation_name", "Unknown Corp")
              end
          end

        _ ->
          character
      end

    character
  end

  # -- NEW SYSTEM NOTIFICATION --

  @doc """
  Sends a notification for a new system found.
  Expects a map with keys: "system_id" and optionally "system_name".
  If "system_name" is missing, falls back to a lookup.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
      handle_test_mode("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    else
      try do
        Stats.increment(:systems)
      rescue
        _ -> :ok
      end

      # Normalize the system data and use the formatter module
      system = normalize_system_data(system)
      generic_notification = Formatter.format_system_notification(system)

      if generic_notification do
        # Convert the generic notification to a Discord-specific format
        discord_embed = Formatter.to_discord_format(generic_notification)

        # Add recent kills to the notification
        discord_embed_with_kills = add_recent_kills_to_embed(discord_embed, system)

        # Send the notification
        send_discord_embed(discord_embed_with_kills, :system_tracking)
      else
        Logger.error("Failed to format system notification: #{inspect(system)}")
        :error
      end
    end
  end

  # Helper function to normalize system data by merging nested data if present
  defp normalize_system_data(system) do
    if Map.has_key?(system, "data") and is_map(system["data"]) do
      Map.merge(system, system["data"])
    else
      system
    end
  end

  # Adds recent kills information to a system notification embed
  defp add_recent_kills_to_embed(embed, system) do
    system_id = Map.get(system, "solar_system_id") ||
                Map.get(system, :solar_system_id) ||
                Map.get(system, "system_id") ||
                Map.get(system, :system_id)

    if system_id do
      Logger.info(
        "[Discord.send_system_activity] Sending recent system activity: System ID #{system_id}"
      )

      case WandererNotifier.Api.ZKill.Service.get_system_kills(system_id, 5) do
        {:ok, zkill_kills} when is_list(zkill_kills) and length(zkill_kills) > 0 ->
          Logger.info(
            "Found #{length(zkill_kills)} recent kills for system #{system_id} from zKillboard"
          )

          kills_text =
            Enum.map_join(zkill_kills, "\n", fn kill ->
              kill_id = Map.get(kill, "killmail_id")
              zkb = Map.get(kill, "zkb") || %{}
              hash = Map.get(zkb, "hash")

              enriched_kill =
                if kill_id != nil and hash do
                  case ESIService.get_esi_kill_mail(kill_id, hash) do
                    {:ok, killmail_data} -> Map.merge(kill, killmail_data)
                    _ -> kill
                  end
                else
                  kill
                end

              victim = Map.get(enriched_kill, "victim") || %{}

              victim_name =
                if Map.has_key?(victim, "character_id") do
                  character_id = Map.get(victim, "character_id")

                  case ESIService.get_character_info(character_id) do
                    {:ok, char_info} -> Map.get(char_info, "name", "Unknown Pilot")
                    _ -> "Unknown Pilot"
                  end
                else
                  "Unknown Pilot"
                end

              ship_type =
                if Map.has_key?(victim, "ship_type_id") do
                  ship_type_id = Map.get(victim, "ship_type_id")

                  case ESIService.get_ship_type_name(ship_type_id) do
                    {:ok, ship_info} -> Map.get(ship_info, "name", "Unknown Ship")
                    _ -> "Unknown Ship"
                  end
                else
                  "Unknown Ship"
                end

              zkb = Map.get(kill, "zkb") || %{}
              kill_value = Map.get(zkb, "totalValue")

              kill_time =
                Map.get(kill, "killmail_time") || Map.get(enriched_kill, "killmail_time")

              time_ago =
                if kill_time do
                  case DateTime.from_iso8601(kill_time) do
                    {:ok, kill_datetime, _} ->
                      diff_seconds = DateTime.diff(DateTime.utc_now(), kill_datetime)

                      cond do
                        diff_seconds < 60 -> "just now"
                        diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
                        diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
                        diff_seconds < 2_592_000 -> "#{div(diff_seconds, 86400)}d ago"
                        true -> "#{div(diff_seconds, 2_592_000)}mo ago"
                      end

                    _ ->
                      ""
                  end
                else
                  ""
                end

              time_display = if time_ago != "", do: " (#{time_ago})", else: ""

              value_text =
                if kill_value do
                  " - #{format_isk_value(kill_value)}"
                else
                  ""
                end

              if victim_name == "Unknown Pilot" do
                "#{ship_type}#{value_text}#{time_display}"
              else
                "[#{victim_name}](https://zkillboard.com/kill/#{kill_id}/) - #{ship_type}#{value_text}#{time_display}"
              end
            end)

          # Add the kills field to the embed
          fields = embed["fields"] || []
          fields = fields ++ [%{"name" => "Recent Kills in System", "value" => kills_text, "inline" => false}]
          Map.put(embed, "fields", fields)

        {:ok, []} ->
          Logger.info("No recent kills found for system #{system_id} from zKillboard")

          # Add a message about no kills
          fields = embed["fields"] || []
          fields = fields ++ [
            %{
              "name" => "Recent Kills in System",
              "value" => "No recent kills found for this system.",
              "inline" => false
            }
          ]
          Map.put(embed, "fields", fields)

        {:error, reason} ->
          Logger.error(
            "Failed to fetch kills for system #{system_id} from zKillboard: #{inspect(reason)}"
          )

          embed
      end
    else
      embed
    end
  end

  # -- HELPER FOR SENDING PAYLOAD --

  defp send_payload(payload, feature) do
    url = build_url(feature)
    json_payload = Jason.encode!(payload)

    Logger.info("Sending Discord API request to URL: #{url} for feature: #{inspect(feature)}")
    Logger.debug("Discord API payload: #{inspect(payload, pretty: true)}")

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        Logger.info("Discord API request successful with status #{status}")
        :ok

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Discord API request failed with status #{status}")
        Logger.error("Discord API error response: #{body}")
        {:error, body}

      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end

  # -- FILE SENDING --

  @doc """
  Sends a file with an optional title and description.

  Implements the Notifiers.Behaviour callback, converts binary data to a file
  and sends it to Discord using the existing file upload functionality.

  ## Parameters
    - filename: The filename to use
    - file_data: The file content as binary data
    - title: Optional title for the message
    - description: Optional description for the message
    - feature: Optional feature to determine the channel to use
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil, feature \\ :general) do
    Logger.info("Discord.Notifier.send_file called with filename: #{filename}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{filename} - #{title || "No title"}")
      :ok
    else
      # Create a temporary file to hold the binary data
      temp_file =
        Path.join(
          System.tmp_dir!(),
          "#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}-#{filename}"
        )

      try do
        # Write the file data to the temp file
        File.write!(temp_file, file_data)

        # Use the existing file sending method
        send_file_path(temp_file, title, description, feature)
      after
        # Clean up the temp file
        File.rm(temp_file)
      end
    end
  end

  # Rename the existing send_file function to send_file_path to avoid conflicts
  def send_file_path(file_path, title \\ nil, description \\ nil, feature \\ :general) do
    Logger.info("Discord.Notifier.send_file_path called with file: #{file_path}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{file_path} - #{title || "No title"}")
    else
      # Build the form data for the file upload
      file_content = File.read!(file_path)
      filename = Path.basename(file_path)

      # Prepare the payload with content if title or description is provided
      payload_json =
        if title || description do
          content =
            case {title, description} do
              {nil, nil} -> ""
              {title, nil} -> title
              {nil, description} -> description
              {title, description} -> "#{title}\n#{description}"
            end

          Jason.encode!(%{"content" => content})
        else
          Jason.encode!(%{})
        end

      # Prepare the URL and headers
      channel = channel_id_for_feature(feature)
      url = "#{@base_url}/#{channel}/messages"

      headers = [
        {"Authorization", "Bot #{bot_token()}"},
        {"User-Agent", "WandererNotifier/1.0"}
      ]

      # Use HTTPoison directly for multipart requests
      boundary =
        "------------------------#{:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)}"

      # Create multipart body manually
      body =
        "--#{boundary}\r\n" <>
          "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n" <>
          "Content-Type: application/octet-stream\r\n\r\n" <>
          file_content <>
          "\r\n--#{boundary}\r\n" <>
          "Content-Disposition: form-data; name=\"payload_json\"\r\n\r\n" <>
          payload_json <>
          "\r\n--#{boundary}--\r\n"

      # Add content-type header with boundary
      headers = [{"Content-Type", "multipart/form-data; boundary=#{boundary}"} | headers]

      # Send the request
      case HTTPoison.post(url, body, headers) do
        {:ok, %{status_code: status_code, body: _response_body}} when status_code in 200..299 ->
          Logger.info("Successfully sent file to Discord")
          :ok

        {:ok, %{status_code: status_code, body: response_body}} ->
          error_msg = "Failed to send file to Discord: HTTP #{status_code}, #{response_body}"
          Logger.error(error_msg)
          {:error, error_msg}

        {:error, %HTTPoison.Error{reason: reason}} ->
          error_msg = "Failed to send file to Discord: #{inspect(reason)}"
          Logger.error(error_msg)
          {:error, error_msg}
      end
    end
  end

  @doc """
  Sends an embed with an image to Discord.

  ## Parameters
    - title: The title of the embed
    - description: The description content
    - image_url: URL of the image to display
    - color: Optional color for the embed
    - feature: Optional feature to determine which channel to use
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_image_embed(title, description, image_url, color \\ @default_embed_color, feature \\ :general) do
    Logger.info(
      "Discord.Notifier.send_image_embed called with title: #{title}, image_url: #{image_url || "nil"}, feature: #{feature}"
    )

    if env() == :test do
      handle_test_mode(
        "DISCORD MOCK IMAGE EMBED: #{title} - #{description} with image: #{image_url} (feature: #{feature})"
      )
    else
      embed = %{
        "title" => title,
        "description" => description,
        "color" => color,
        "image" => %{
          "url" => image_url
        }
      }

      payload = %{"embeds" => [embed]}

      Logger.info("Discord image embed payload built, sending to Discord API with feature: #{feature}")
      send_payload(payload, feature)
    end
  end
end
