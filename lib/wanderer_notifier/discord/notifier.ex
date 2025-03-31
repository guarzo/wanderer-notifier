defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Api.ESI.Service, as: ESI
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Config.{Application, Notifications}
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Discord.ComponentBuilder
  alias WandererNotifier.Discord.Constants
  alias WandererNotifier.Discord.FeatureFlags
  alias WandererNotifier.Discord.NeoClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Determiner
  alias WandererNotifier.Notifiers.StructuredFormatter

  @behaviour WandererNotifier.Notifiers.Behaviour

  # Default embed colors
  @default_embed_color 0x3498DB
  # Blue for Pulsar
  # @wormhole_color 0x428BCA
  # # Green for highsec
  # @highsec_color 0x5CB85C
  # # Yellow/orange for lowsec
  # @lowsec_color 0xE28A0D
  # # Red for nullsec
  # @nullsec_color 0xD9534F

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env, do: Application.get_env()

  # Helper function to handle test mode logging and response
  defp handle_test_mode(log_message) do
    # Always log in test mode for test assertions
    Logger.info(log_message)
    :ok
  end

  defp channel_id do
    case env() do
      :test -> "test_channel_id"
      _ -> Notifications.get_discord_channel_id_for(:general)
    end
  end

  defp bot_token do
    case env() do
      :test -> "test_bot_token"
      _ -> Notifications.get_discord_bot_token()
    end
  end

  defp build_url, do: Constants.messages_url(channel_id())

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{bot_token()}"}
    ]
  end

  # -- HELPER FUNCTIONS --

  # Helper to determine type of value for logging
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_integer(term), do: "integer"
  defp typeof(term) when is_float(term), do: "float"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(term) when is_pid(term), do: "pid"
  defp typeof(term) when is_reference(term), do: "reference"
  defp typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
  defp typeof(_), do: "unknown"

  # -- MESSAGE SENDING --

  @impl WandererNotifier.Notifiers.Behaviour
  def send_message(message, feature \\ nil) do
    AppLogger.processor_info("Discord message requested")

    if env() == :test do
      handle_test_mode("DISCORD MOCK MESSAGE: #{message}")
    else
      # Use feature flag to determine client (now defaults to Nostrum)
      use_nostrum = FeatureFlags.use_nostrum?()

      AppLogger.processor_info("Sending Discord message",
        client: if(use_nostrum, do: "Nostrum", else: "HTTP"),
        message_length: String.length(message)
      )

      if use_nostrum do
        # Use Nostrum client
        NeoClient.send_message(message)
      else
        # Use legacy HTTP approach
        payload = %{"content" => message}
        send_payload(payload, feature)
      end
    end
  end

  @spec send_embed(any(), any(), any(), any(), any()) :: :ok | {:error, any()}
  @doc """
  Sends a basic embed message to Discord.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color, feature \\ nil) do
    AppLogger.processor_info("Discord embed requested",
      title: title,
      url: url || "nil"
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED: #{title} - #{description}")
    else
      # Use feature flag to determine client (now defaults to Nostrum)
      use_nostrum = FeatureFlags.use_nostrum?()

      # Build embed payload
      embed = build_embed_payload(title, description, url, color)

      if use_nostrum do
        # For Nostrum, we just need the embed object from the payload
        discord_embed = embed["embeds"] |> List.first()
        NeoClient.send_embed(discord_embed)
      else
        # Use legacy HTTP approach
        send_payload(embed, feature)
      end
    end
  end

  defp build_embed_payload(title, description, url, color) do
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color
    }

    # Add URL if provided
    embed =
      if url do
        Map.put(embed, "url", url)
      else
        embed
      end

    # Return final payload with embed
    %{"embeds" => [embed]}
  end

  @doc """
  Sends a Discord embed using the Discord API.
  """
  def send_discord_embed(embed, _feature \\ nil) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED (JSON): #{inspect(embed)}")
    else
      # Use feature flag to determine client (now defaults to Nostrum)
      use_nostrum = FeatureFlags.use_nostrum?()

      if use_nostrum do
        # For Nostrum, send directly through the NeoClient
        AppLogger.processor_info("Using Nostrum client for structured embed")
        NeoClient.send_embed(embed)
      else
        # Legacy HTTP approach
        AppLogger.processor_info("Using HTTP client for structured embed")
        payload = %{"embeds" => [embed]}
        send_payload(payload)
      end
    end
  end

  # Ensure the killmail has a system name if missing
  defp enrich_with_system_name(%Killmail{} = killmail) do
    # Get system_id from the esi_data
    system_id = get_system_id_from_killmail(killmail)

    # Check if we need to get the system name
    if system_id do
      # Get system name using the same approach as in kill_processor
      system_name = get_system_name(system_id)

      AppLogger.processor_debug("Enriching killmail with system name",
        system_id: system_id,
        system_name: system_name
      )

      # Add system name to esi_data
      new_esi_data = Map.put(killmail.esi_data || %{}, "solar_system_name", system_name)
      %{killmail | esi_data: new_esi_data}
    else
      killmail
    end
  end

  # Get system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    if killmail.esi_data do
      Map.get(killmail.esi_data, "solar_system_id")
    else
      nil
    end
  end

  # Helper function to get system name with caching
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case ESI.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      {:error, :not_found} -> "Unknown-#{system_id}"
      _ -> nil
    end
  end

  # Send formatted notification to Discord
  defp send_to_discord(formatted_notification, feature) do
    # Skip actual sending in test mode
    if env() == :test do
      handle_test_mode("DISCORD TEST NOTIFICATION: #{inspect(feature)}")
    else
      # Convert to Discord format
      discord_embed = StructuredFormatter.to_discord_format(formatted_notification)

      # Check if components are enabled and available
      components = Map.get(formatted_notification, :components, [])
      use_components = FeatureFlags.components_enabled?() and components != []

      if use_components do
        # If components are enabled, use enhanced format
        AppLogger.processor_info("Using Discord components for #{feature} notification")
        send_embed_with_components(discord_embed, components, feature)
      else
        # Otherwise use standard embed
        AppLogger.processor_info("Using standard embeds for #{feature} notification",
          components_enabled: FeatureFlags.components_enabled?()
        )

        payload = %{"embeds" => [discord_embed]}
        send_payload(payload, feature)
      end
    end
  end

  # -- NEW TRACKED CHARACTER NOTIFICATION --

  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_tracked_character_notification(character)
      when is_struct(character, WandererNotifier.Data.Character) do
    if env() == :test do
      handle_test_mode(
        "DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character.character_id}"
      )
    else
      # Extract character ID for deduplication check
      character_id = character.character_id

      # Check if this is a duplicate notification
      case Determiner.check_deduplication(
             :character,
             character_id
           ) do
        {:ok, :send} ->
          # This is not a duplicate, proceed with notification
          AppLogger.processor_info("Processing new character notification",
            character_name: character.name,
            character_id: character.character_id
          )

          # Create notification with StructuredFormatter
          generic_notification = StructuredFormatter.format_character_notification(character)
          send_to_discord(generic_notification, :character_tracking)

        {:ok, :skip} ->
          # This is a duplicate, skip notification
          AppLogger.processor_info("Skipping duplicate character notification",
            character_name: character.name,
            character_id: character.character_id
          )

          :ok

        {:error, reason} ->
          # Error during deduplication check, log it
          AppLogger.processor_error("Error checking character deduplication",
            character_id: character_id,
            character_name: character.name,
            error: inspect(reason)
          )

          # Default to sending notification in case of error
          AppLogger.processor_info("Proceeding with notification despite deduplication error",
            character_id: character_id,
            character_name: character.name
          )

          # Create notification with StructuredFormatter
          generic_notification = StructuredFormatter.format_character_notification(character)
          send_to_discord(generic_notification, :character_tracking)
      end
    end
  end

  # -- NEW SYSTEM NOTIFICATION --

  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_system_notification(system) do
    # Log system details before processing to diagnose cache issues
    AppLogger.processor_info(
      "[NEW_SYSTEM_NOTIFICATION] Processing system notification request",
      system_type: typeof(system),
      system_preview: inspect(system, limit: 200)
    )

    if env() == :test do
      # Get system ID safely regardless of structure
      system_id = extract_system_id(system)
      handle_test_mode("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    else
      # Extract system data safely with fallbacks
      system_id = extract_system_id(system)
      system_name = extract_system_name(system)

      # Log extracted details for debugging
      AppLogger.processor_info(
        "[NEW_SYSTEM_NOTIFICATION] Extracted system details",
        system_id: system_id,
        system_name: system_name
      )

      # Check if this is a duplicate notification
      case Determiner.check_deduplication(:system, system_id) do
        {:ok, :send} ->
          # This is not a duplicate, proceed with notification
          AppLogger.processor_info("Processing new system notification",
            system_id: system_id,
            system_name: system_name
          )

          # Convert to MapSystem struct if needed for formatter
          map_system = ensure_map_system(system)

          # Create notification with StructuredFormatter - JUST LIKE CHARACTER NOTIFICATIONS
          AppLogger.processor_info("Using StructuredFormatter for system notification")
          generic_notification = StructuredFormatter.format_system_notification(map_system)

          # Send using the standard send_to_discord helper
          send_to_discord(generic_notification, :system_tracking)

          # Record stats
          Stats.increment(:systems)

          :ok

        {:ok, :skip} ->
          # This is a duplicate, skip notification
          AppLogger.processor_info("Skipping duplicate system notification",
            system_id: system_id,
            system_name: system_name
          )

          :ok

        {:error, reason} ->
          # Error during deduplication check, log it
          AppLogger.processor_error("Error checking system deduplication",
            system_id: system_id,
            system_name: system_name,
            error: inspect(reason)
          )

          # Default to sending notification in case of error
          AppLogger.processor_info("Proceeding with notification despite deduplication error",
            system_id: system_id,
            system_name: system_name
          )

          # Recursively call self with same system data
          send_new_system_notification(system)
      end
    end
  end

  # Helper to convert to MapSystem struct if needed
  defp ensure_map_system(system) do
    if is_struct(system, MapSystem) do
      # Already a MapSystem, just return it
      system
    else
      # Try to create MapSystem from a map or other structure
      try do
        # Check if we need to convert it
        if is_map(system) do
          MapSystem.new(system)
        else
          # Log error and return original
          AppLogger.processor_error(
            "[Discord.Notifier] Cannot convert to MapSystem: #{inspect(system)}"
          )

          system
        end
      rescue
        e ->
          # Log error and return original on conversion failure
          AppLogger.processor_error(
            "[Discord.Notifier] Failed to convert to MapSystem: #{Exception.message(e)}"
          )

          system
      end
    end
  end

  # Safely extract system ID
  defp extract_system_id(system) do
    # Check solar_system_id first (most common field)
    system_id = extract_id_field(system, [:solar_system_id, "solar_system_id"])

    # If not found, try more generic id fields
    if system_id, do: system_id, else: extract_id_field(system, [:id, "id"]) || "unknown"
  end

  # Helper to extract ID from various field names
  defp extract_id_field(system, field_names) do
    Enum.find_value(field_names, fn field ->
      cond do
        is_struct(system) && Map.has_key?(system, field) -> Map.get(system, field)
        is_map(system) && Map.has_key?(system, field) -> Map.get(system, field)
        true -> nil
      end
    end)
  end

  # Safely extract system name
  defp extract_system_name(system) do
    extract_field_value(system, [:name, "name"], "Unknown System")
  end

  # Helper to extract a field with a default value
  defp extract_field_value(system, field_names, default) do
    Enum.find_value(field_names, default, fn field ->
      cond do
        is_struct(system) && Map.has_key?(system, field) -> Map.get(system, field)
        is_map(system) && Map.has_key?(system, field) -> Map.get(system, field)
        true -> nil
      end
    end)
  end

  # -- PAYLOAD SENDING --

  defp send_payload(payload, feature \\ nil) do
    # Use feature flag to determine client (now defaults to Nostrum)
    use_nostrum = FeatureFlags.use_nostrum?()

    if use_nostrum do
      send_via_nostrum(payload, feature)
    else
      send_via_http(payload, feature)
    end
  end

  # Send via direct HTTP request (legacy approach)
  defp send_via_http(payload, feature) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    AppLogger.processor_info("Sending Discord API request via HTTP",
      url: url,
      feature: feature
    )

    AppLogger.processor_debug("Discord API payload details",
      payload_size: byte_size(json_payload)
    )

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        AppLogger.processor_info("Discord API request successful",
          status: status,
          feature: feature
        )

        :ok

      {:ok, %{status_code: 429, body: body}} ->
        # Parse retry_after from response for rate limiting
        retry_after =
          case Jason.decode(body) do
            {:ok, decoded} -> Map.get(decoded, "retry_after", 5) * 1000
            _ -> 5000
          end

        AppLogger.processor_error("Discord API rate limit hit",
          retry_after: retry_after,
          feature: feature
        )

        {:error, {:rate_limited, retry_after}}

      {:ok, %{status_code: status, body: body}} ->
        AppLogger.processor_error("Discord API request failed",
          status: status,
          response: body,
          feature: feature
        )

        {:error, body}

      {:error, err} ->
        AppLogger.processor_error("Discord API request error",
          error: inspect(err),
          feature: feature
        )

        {:error, err}
    end
  end

  # Send via Nostrum (new approach)
  defp send_via_nostrum(payload, feature) do
    AppLogger.processor_info("Sending Discord API request via Nostrum",
      feature: feature
    )

    # Delegate to appropriate handler based on payload structure
    cond do
      text_message_payload?(payload) ->
        handle_text_message_payload(payload)

      embed_with_components_payload?(payload) ->
        handle_embed_with_components_payload(payload)

      embed_only_payload?(payload) ->
        handle_embed_only_payload(payload)

      true ->
        handle_unknown_payload(payload)
    end
  end

  # Helper to check if payload is a simple text message
  defp text_message_payload?(payload) do
    Map.has_key?(payload, "content") and
      (not Map.has_key?(payload, "embeds") or Enum.empty?(Map.get(payload, "embeds", [])))
  end

  # Helper to handle text message payloads
  defp handle_text_message_payload(payload) do
    message = Map.get(payload, "content")
    NeoClient.send_message(message)
  end

  # Helper to check if payload has embeds and components
  defp embed_with_components_payload?(payload) do
    Map.has_key?(payload, "embeds") and Map.has_key?(payload, "components")
  end

  # Helper to handle embeds with components payloads
  defp handle_embed_with_components_payload(payload) do
    embeds = Map.get(payload, "embeds", [])
    components = Map.get(payload, "components", [])

    if Enum.empty?(embeds) do
      AppLogger.processor_warn("Empty embeds in payload, skipping Nostrum API call")
      :ok
    else
      embed = List.first(embeds)
      NeoClient.send_message_with_components(embed, components)
    end
  end

  # Helper to check if payload has only embeds (no components)
  defp embed_only_payload?(payload) do
    Map.has_key?(payload, "embeds")
  end

  # Helper to handle embeds-only payloads
  defp handle_embed_only_payload(payload) do
    embeds = Map.get(payload, "embeds", [])

    if Enum.empty?(embeds) do
      AppLogger.processor_warn("Empty embeds in payload, skipping Nostrum API call")
      :ok
    else
      embed = List.first(embeds)
      NeoClient.send_embed(embed)
    end
  end

  # Helper to handle unknown payload structures
  defp handle_unknown_payload(payload) do
    AppLogger.processor_error("Unknown payload structure for Nostrum",
      payload: inspect(payload, limit: 200)
    )

    {:error, :unknown_payload_structure}
  end

  # -- FILE SENDING --

  @doc """
  Sends a file to Discord with an optional title and description.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil, _feature \\ nil) do
    AppLogger.processor_info("Sending file to Discord",
      filename: filename,
      title: title
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{filename} - #{title || "No title"}")
    else
      # Use feature flag to determine client (now defaults to Nostrum)
      use_nostrum = FeatureFlags.use_nostrum?()

      if use_nostrum do
        NeoClient.send_file(filename, file_data, title, description)
      else
        # Use legacy HTTP approach
        url = build_url()

        {_boundary, body, file_headers} =
          prepare_file_upload(filename, file_data, title, description)

        send_multipart_request(url, file_headers, body)
      end
    end
  end

  # Prepare the multipart data for file upload
  defp prepare_file_upload(filename, file_data, title, description) do
    # Create form data with file and JSON payload
    boundary = "----------------------------#{:rand.uniform(999_999_999)}"

    # Prepare JSON payload
    json_payload = create_file_json_payload(filename, title, description)

    # Build multipart request body
    body = [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"payload_json\"\r\n\r\n",
      json_payload,
      "\r\n--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
      "Content-Type: application/octet-stream\r\n\r\n",
      file_data,
      "\r\n--#{boundary}--\r\n"
    ]

    # Custom headers for multipart request
    file_headers = [
      {"Content-Type", "multipart/form-data; boundary=#{boundary}"},
      {"Authorization", "Bot #{bot_token()}"}
    ]

    {boundary, body, file_headers}
  end

  # Create the JSON payload for file upload
  defp create_file_json_payload(filename, title, description) do
    if title || description do
      embed = %{
        "title" => title || filename,
        "description" => description || "",
        "color" => @default_embed_color
      }

      Jason.encode!(%{"embeds" => [embed]})
    else
      "{}"
    end
  end

  # Send a multipart request
  defp send_multipart_request(url, headers, body) do
    case HttpClient.request("POST", url, headers, body) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        AppLogger.processor_info("Successfully sent file to Discord", status: status)
        :ok

      {:ok, %{status_code: status, body: response_body}} ->
        AppLogger.processor_error("Failed to send file to Discord",
          status: status,
          response: inspect(response_body)
        )

        {:error, "Discord API error: #{status}"}

      {:error, reason} ->
        AppLogger.processor_error("Error sending file to Discord", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Sends an embed with an image to Discord.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_image_embed(
        title,
        description,
        image_url,
        color \\ @default_embed_color,
        feature \\ nil
      ) do
    AppLogger.processor_info("Sending image embed to Discord",
      title: title,
      image_url: image_url || "nil"
    )

    if env() == :test do
      handle_test_mode(
        "DISCORD MOCK IMAGE EMBED: #{title} - #{description} with image: #{image_url}"
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

      AppLogger.processor_info("Discord image embed payload built, sending to Discord API")
      send_payload(payload, feature)
    end
  end

  @doc """
  Routes different types of notifications to the appropriate function.
  This is a helper function used by the NotifierFactory.
  """
  def send_notification(:send_message, [message]) when is_binary(message) do
    send_message(message)
  end

  def send_notification(:send_embed, [title, description, url, color]) do
    send_embed(title, description, url, color)
  end

  def send_notification(:send_embed, [title, description]) do
    send_embed(title, description)
  end

  def send_notification(:send_embed, [title, description, url]) do
    send_embed(title, description, url)
  end

  def send_notification(type, data) do
    AppLogger.processor_error("Unknown notification type", type: type, data: inspect(data))
    {:error, :unknown_notification_type}
  end

  @doc """
  Sends a kill embed.
  """
  def send_kill_embed(kill, killmail_id) do
    send_enriched_kill_embed(kill, killmail_id)
  end

  # Additional required method from the behavior
  @impl WandererNotifier.Notifiers.Behaviour
  def send_kill_notification(kill_data) do
    # Extract kill ID for logging
    kill_id = Map.get(kill_data, "killmail_id") || Map.get(kill_data, :killmail_id) || "unknown"

    # Delegate to the existing method that handles formatting and sending
    kill_id_str = if is_integer(kill_id), do: Integer.to_string(kill_id), else: kill_id
    send_kill_embed(kill_data, kill_id_str)
  end

  # -- EMBEDS WITH COMPONENTS --

  @doc """
  Sends an embed with interactive components to Discord.
  """
  def send_embed_with_components(embed, components, feature \\ nil) do
    AppLogger.processor_info("Discord embed with components requested",
      component_count: length(components)
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED WITH COMPONENTS: #{inspect(embed)}")
    else
      # Use feature flag to determine client (now defaults to Nostrum)
      use_nostrum = FeatureFlags.use_nostrum?()

      if use_nostrum do
        NeoClient.send_message_with_components(embed, components)
      else
        # Use legacy HTTP approach
        payload = %{
          "embeds" => [embed],
          "components" => components
        }

        AppLogger.processor_info(
          "Discord embed with components payload built, sending to Discord API"
        )

        send_payload(payload, feature)
      end
    end
  end

  # -- ENRICHED KILL NOTIFICATION --

  @doc """
  Send an enriched kill embed to Discord with interactive components.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(killmail, kill_id) when is_struct(killmail, Killmail) do
    AppLogger.processor_debug("Preparing to format killmail for Discord", kill_id: kill_id)

    # Ensure the killmail has a system name if system_id is present
    enriched_killmail = enrich_with_system_name(killmail)

    # Format the kill notification
    formatted_embed = StructuredFormatter.format_kill_notification(enriched_killmail)

    # Only add components if the feature flag is enabled
    enhanced_notification =
      if FeatureFlags.components_enabled?() do
        # Add interactive components based on the killmail
        components = [ComponentBuilder.kill_action_row(kill_id)]

        AppLogger.processor_debug("Adding interactive components to kill notification",
          kill_id: kill_id
        )

        # Add components to the notification
        Map.put(formatted_embed, :components, components)
      else
        # Use standard format without components
        AppLogger.processor_debug(
          "Using standard embed format for kill notification (components disabled)",
          kill_id: kill_id
        )

        formatted_embed
      end

    send_to_discord(enhanced_notification, "kill")
  end
end
