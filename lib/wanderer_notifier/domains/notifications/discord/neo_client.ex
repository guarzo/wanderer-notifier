defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient do
  @moduledoc """
  Nostrum-based Discord client implementation.
  Leverages the Nostrum library for interaction with Discord API and event handling.
  """
  use Nostrum.Consumer

  alias Nostrum.Api.Message
  alias Nostrum.Struct.Embed
  alias WandererNotifier.Shared.Config
  require Logger
  alias WandererNotifier.Shared.Utils.TimeUtils
  alias WandererNotifier.Shared.Config.Utils

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @doc """
  Gets the configured Discord channel ID as an integer.
  Returns the normalized channel ID or nil if not set or invalid.
  """
  def channel_id do
    try do
      raw_id = Config.discord_channel_id()
      Logger.debug("Fetching Discord channel ID")

      # First try to normalize the channel ID
      normalized_id = normalize_channel_id(raw_id)

      # If we couldn't normalize it, try some fallbacks
      if is_nil(normalized_id) do
        Logger.warning("Could not normalize Discord channel ID, trying fallbacks", category: :api)

        # Try other channel IDs as fallbacks
        cond do
          fallback = normalize_channel_id(Config.discord_system_channel_id()) ->
            Logger.info("Using system channel ID as fallback", fallback: fallback, category: :api)
            fallback

          fallback = normalize_channel_id(Config.discord_kill_channel_id()) ->
            Logger.info("Using kill channel ID as fallback", fallback: fallback, category: :api)
            fallback

          fallback = normalize_channel_id(Config.discord_character_channel_id()) ->
            Logger.info("Using character channel ID as fallback",
              fallback: fallback,
              category: :api
            )

            fallback

          true ->
            Logger.error("No valid Discord channel ID available, notifications may fail",
              category: :api
            )

            nil
        end
      else
        normalized_id
      end
    rescue
      e ->
        Logger.error("Error getting Discord channel ID",
          error: Exception.message(e),
          category: :api
        )

        nil
    end
  end

  # -- MESSAGING API --

  @doc """
  Sends an embed message to Discord using Nostrum.

  ## Parameters
    - embed: A map containing the embed data
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_embed(embed, override_channel_id \\ nil) do
    if env() == :test do
      log_test_embed(embed)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_embed_to_channel(embed, target_channel)
    end
  end

  # Log test mode embed without sending
  defp log_test_embed(embed) do
    Logger.info("TEST MODE: Would send embed to Discord via Nostrum",
      embed: inspect(embed),
      category: :api
    )

    :ok
  end

  # Resolve the target channel ID
  defp resolve_target_channel(override_channel_id) do
    if is_nil(override_channel_id) do
      channel_id()
    else
      normalize_channel_id(override_channel_id)
    end
  end

  # Send embed to the specified channel
  defp send_embed_to_channel(embed, target_channel) do
    # Validate channel ID
    case target_channel do
      nil ->
        Logger.error("Failed to send embed: nil channel ID",
          embed_type: typeof(embed),
          embed_title:
            if(is_map(embed), do: Map.get(embed, "title", "Unknown title"), else: "Unknown"),
          category: :api
        )

        {:error, :nil_channel_id}

      channel_id when is_binary(channel_id) and channel_id != "" ->
        # Channel ID is already a non-empty string
        send_embed_to_valid_channel(embed, channel_id)

      channel_id when is_integer(channel_id) ->
        # Convert integer channel ID to string
        send_embed_to_valid_channel(embed, to_string(channel_id))

      _ ->
        Logger.error("Failed to send embed: invalid channel ID",
          channel_id: target_channel,
          embed_type: typeof(embed),
          embed_title:
            if(is_map(embed), do: Map.get(embed, "title", "Unknown title"), else: "Unknown"),
          category: :api
        )

        {:error, :invalid_channel_id}
    end
  end

  # Helper function to send embed to a validated channel ID
  defp send_embed_to_valid_channel(embed, channel_id) do
    # Convert to Nostrum.Struct.Embed
    discord_embed = convert_to_nostrum_embed(embed)

    # Check if there's content to send with the embed
    content = Map.get(embed, :content, "")

    # Use Nostrum.Api.Message.create with embeds (plural) as an array
    try do
      channel_id_int = String.to_integer(channel_id)

      if is_binary(content) and String.trim(content) != "" do
        send_discord_message(channel_id_int, discord_embed, content)
      else
        send_discord_message(channel_id_int, discord_embed)
      end
    rescue
      e ->
        handle_exception(e, channel_id)
    end
  end

  # Send message to Discord and handle the response
  defp send_discord_message(channel_id_int, discord_embed) do
    send_discord_message_with_retry(channel_id_int, discord_embed, nil, 0)
  end

  # Send message with content to Discord and handle the response
  defp send_discord_message(channel_id_int, discord_embed, content)
       when is_binary(content) and content != "" do
    send_discord_message_with_retry(channel_id_int, discord_embed, content, 0)
  end

  defp send_discord_message_with_retry(channel_id_int, discord_embed, content, attempt)
       when attempt < 5 do
    context = build_retry_context(channel_id_int, discord_embed, content, attempt)

    log_api_attempt(context.channel_id, context.has_content, context.rally_id, context.attempt)

    task = create_discord_api_task(context.channel_id, discord_embed, content, context.rally_id)

    handle_task_result(task, context)
  end

  defp send_discord_message_with_retry(_channel_id_int, _discord_embed, _content, attempt) do
    Logger.error("Discord API call failed after #{attempt} attempts", category: :api)
    {:error, :discord_timeout}
  end

  defp build_retry_context(channel_id, discord_embed, content, attempt) do
    %{
      channel_id: channel_id,
      discord_embed: discord_embed,
      content: content,
      attempt: attempt,
      start_time: System.monotonic_time(:millisecond),
      rally_id: extract_rally_id(discord_embed),
      has_content: content != nil
    }
  end

  defp handle_task_result(task, context) do
    case Task.yield(task, 15_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, _message}} ->
        handle_success(context.start_time, context.rally_id, context.attempt)

      {:ok, {:error, %{status_code: 429} = response}} ->
        handle_rate_limit(response, context.channel_id, context.start_time, context.rally_id)

      {:ok, {:error, response}} ->
        do_retry(response, context)

      nil ->
        do_timeout_retry(context)
    end
  end

  defp do_retry(response, context) do
    elapsed = System.monotonic_time(:millisecond) - context.start_time

    Logger.warning(
      "[RALLY_TIMING] Discord API error on attempt #{context.attempt + 1} after #{elapsed}ms, retrying...",
      error: inspect(response),
      rally_id: context.rally_id,
      category: :api
    )

    delay =
      2
      |> :math.pow(context.attempt)
      |> Kernel.*(1000)
      |> min(10_000)
      |> round()

    Process.sleep(delay)

    send_discord_message_with_retry(
      context.channel_id,
      context.discord_embed,
      context.content,
      context.attempt + 1
    )
  end

  defp do_timeout_retry(context) do
    elapsed = System.monotonic_time(:millisecond) - context.start_time

    Logger.warning(
      "[RALLY_TIMING] Discord API call timed out after 15 seconds on attempt #{context.attempt + 1} (#{elapsed}ms total)",
      channel_id: context.channel_id,
      rally_id: context.rally_id,
      category: :api
    )

    delay =
      2
      |> :math.pow(context.attempt)
      |> Kernel.*(1000)
      |> min(10_000)
      |> round()

    Process.sleep(delay)

    send_discord_message_with_retry(
      context.channel_id,
      context.discord_embed,
      context.content,
      context.attempt + 1
    )
  end

  defp extract_rally_id(discord_embed) do
    case discord_embed do
      %{description: desc} when is_binary(desc) ->
        if Regex.match?(~r/rally point/i, desc), do: "rally_point", else: nil

      _ ->
        nil
    end
  end

  defp log_api_attempt(channel_id, has_content, rally_id, attempt) do
    Logger.info("[RALLY_TIMING] Starting Discord API call attempt #{attempt + 1}",
      channel_id: channel_id,
      has_content: has_content,
      rally_id: rally_id,
      category: :api
    )
  end

  defp create_discord_api_task(channel_id_int, discord_embed, content, rally_id) do
    Task.async(fn ->
      api_start = System.monotonic_time(:millisecond)

      Logger.info("[RALLY_TIMING] Calling Message.create",
        rally_id: rally_id,
        category: :api
      )

      result = call_discord_api(channel_id_int, discord_embed, content)

      Logger.info(
        "[RALLY_TIMING] Message.create returned after #{System.monotonic_time(:millisecond) - api_start}ms",
        rally_id: rally_id,
        result: inspect(elem(result, 0)),
        category: :api
      )

      result
    end)
  end

  defp call_discord_api(channel_id_int, discord_embed, content) do
    # Add debugging for Discord API calls
    Logger.info(
      "Discord API call starting - Channel: #{channel_id_int}, Content: #{not is_nil(content)}"
    )

    result =
      if content do
        Message.create(channel_id_int, content: content, embeds: [discord_embed])
      else
        Message.create(channel_id_int, embeds: [discord_embed])
      end

    Logger.info("Discord API call result: #{inspect(elem(result, 0))}")
    result
  end

  defp handle_success(start_time, rally_id, attempt) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if attempt > 0 do
      Logger.info(
        "[RALLY_TIMING] Discord API call succeeded on attempt #{attempt + 1} after #{elapsed}ms",
        rally_id: rally_id,
        category: :api
      )
    else
      Logger.info("[RALLY_TIMING] Discord API call succeeded after #{elapsed}ms",
        rally_id: rally_id,
        category: :api
      )
    end

    :ok
  end

  defp handle_rate_limit(response, _channel_id_int, start_time, rally_id) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    Logger.warning("[RALLY_TIMING] Discord rate limited after #{elapsed}ms",
      rally_id: rally_id,
      category: :api
    )

    retry_after = get_retry_after(Map.get(response, :response))
    Logger.error("Discord rate limit hit via Nostrum", retry_after: retry_after, category: :api)
    {:error, {:rate_limited, retry_after}}
  end

  # Handle exceptions during message sending
  defp handle_exception(e, channel_id) do
    Logger.error("Exception in send_embed_to_channel",
      error: Exception.message(e),
      channel_id: channel_id,
      category: :api
    )

    {:error, {:exception, Exception.message(e)}}
  end

  @doc """
  Sends a message with components to Discord using Nostrum.

  ## Parameters
    - embed: A map containing the embed data
    - components: A list of component rows (buttons, select menus, etc.)
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_message_with_components(embed, components, override_channel_id \\ nil) do
    if env() == :test do
      log_test_message_with_components(embed, components)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_message_with_components_to_channel(embed, components, target_channel)
    end
  end

  # Log test mode message with components without sending
  defp log_test_message_with_components(embed, components) do
    Logger.info("TEST MODE: Would send message with components via Nostrum",
      embed: inspect(embed),
      components: inspect(components),
      category: :api
    )

    :ok
  end

  # Send message with components to the specified channel
  defp send_message_with_components_to_channel(_embed, _components, nil) do
    Logger.error("Failed to send message with components: nil channel ID", category: :api)
    {:error, :nil_channel_id}
  end

  defp send_message_with_components_to_channel(embed, components, target_channel) do
    # Convert to Nostrum structs
    discord_embed = convert_to_nostrum_embed(embed)
    discord_components = components
    # Log detailed info about what we're sending
    Logger.debug("Sending message with components via Nostrum",
      channel_id: target_channel,
      embed_type: typeof(discord_embed),
      category: :api
    )

    case Message.create(target_channel,
           embed: discord_embed,
           components: discord_components
         ) do
      {:ok, _message} ->
        :ok

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)

        Logger.error("Discord rate limit hit via Nostrum",
          retry_after: retry_after,
          category: :api
        )

        {:error, {:rate_limited, retry_after}}

      {:error, error} ->
        Logger.error("Failed to send message with components via Nostrum",
          error: inspect(error),
          category: :api
        )

        {:error, error}
    end
  end

  @doc """
  Sends a simple text message to Discord using Nostrum.

  ## Parameters
    - message: The text message to send
    - override_channel_id: Optional channel ID to override the default

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_message(message, override_channel_id \\ nil) do
    if env() == :test do
      log_test_message(message)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_message_to_channel(message, target_channel)
    end
  end

  # Log test mode message without sending
  defp log_test_message(message) do
    Logger.info("TEST MODE: Would send message via Nostrum", message: message, category: :api)
    :ok
  end

  # Send message to the specified channel
  defp send_message_to_channel(_message, nil) do
    Logger.error("Failed to send message: nil channel ID", category: :api)
    {:error, :nil_channel_id}
  end

  defp send_message_to_channel(message, target_channel) do
    Logger.debug("Sending text message via Nostrum",
      channel_id: target_channel,
      message_length: String.length(message),
      category: :api
    )

    # Convert channel ID to integer for Nostrum API
    channel_id =
      if is_binary(target_channel), do: String.to_integer(target_channel), else: target_channel

    case Message.create(channel_id, content: message) do
      {:ok, _response} ->
        :ok

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)

        Logger.error("Discord rate limit hit via Nostrum",
          retry_after: retry_after,
          category: :api
        )

        {:error, {:rate_limited, retry_after}}

      {:error, error} ->
        Logger.error("Failed to send message via Nostrum")
        {:error, error}
    end
  end

  # -- FILE HANDLING --

  @doc """
  Sends a file to Discord with an optional title and description using Nostrum.

  ## Parameters
    - filename: The name of the file to send
    - file_data: The binary content of the file
    - title: The title for the Discord embed (optional)
    - description: The description for the Discord embed (optional)
    - override_channel_id: Optional channel ID to override the default
    - custom_embed: A custom embed to use instead of the default one (optional)

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_file(
        filename,
        file_data,
        title \\ nil,
        description \\ nil,
        override_channel_id \\ nil,
        custom_embed \\ nil
      ) do
    Logger.info("Sending file to Discord via Nostrum", filename: filename, category: :api)

    if env() == :test do
      log_test_file(filename, title, description)
    else
      target_channel = resolve_target_channel(override_channel_id)
      send_file_to_channel(filename, file_data, title, description, target_channel, custom_embed)
    end
  end

  # Log test mode file without sending
  defp log_test_file(filename, title, description) do
    Logger.info("TEST MODE: Would send file to Discord via Nostrum",
      filename: filename,
      title: title,
      description: description,
      category: :api
    )

    :ok
  end

  # Send file to the specified channel
  defp send_file_to_channel(_filename, _file_data, _title, _description, nil, _custom_embed) do
    Logger.error("Failed to send file: nil channel ID", category: :api)
    {:error, :nil_channel_id}
  end

  defp send_file_to_channel(filename, file_data, title, description, target_channel, custom_embed) do
    # Create the embed (use custom if provided, otherwise create default)
    embed = create_file_embed(filename, title, description, custom_embed)

    Logger.debug("Sending file with embed via Nostrum",
      channel_id: target_channel,
      filename: filename,
      embed: inspect(embed),
      category: :api
    )

    case Message.create(target_channel,
           file: %{name: filename, body: file_data},
           embeds: [embed]
         ) do
      {:ok, _message} ->
        :ok

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)

        Logger.error("Discord rate limit hit via Nostrum",
          retry_after: retry_after,
          category: :api
        )

        {:error, {:rate_limited, retry_after}}

      {:error, error} ->
        Logger.error("Failed to send file via Nostrum")
        {:error, error}
    end
  end

  # Create embed for file upload
  defp create_file_embed(filename, title, description, custom_embed) do
    if custom_embed do
      embed = convert_to_nostrum_embed(custom_embed)
      %{embed | image: %{url: "attachment://#{filename}"}}
    else
      %Embed{
        title: title,
        description: description,
        timestamp: TimeUtils.now(),
        color: 3_447_003,
        image: %{url: "attachment://#{filename}"}
      }
    end
  end

  # -- EVENT HANDLING --

  @doc """
  Handle interaction events from Discord.
  This allows responding to button clicks, select menu choices, etc.
  """
  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    Logger.debug("Received Discord interaction",
      type: interaction.type,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id,
      category: :api
    )

    :noop
  end

  @impl true
  def handle_event(_event) do
    :noop
  end

  # -- HELPERS --

  defp normalize_channel_id(channel_id) do
    try do
      Logger.debug("Normalizing channel ID",
        raw_channel_id: "#{inspect(channel_id)}",
        category: :api
      )

      # First clean up the ID
      clean_id = clean_channel_id(channel_id)

      # Then process the cleaned ID
      process_cleaned_channel_id(clean_id)
    rescue
      e ->
        Logger.error("Error normalizing channel ID", error: Exception.message(e), category: :api)

        nil
    end
  end

  # Clean up the channel ID
  defp clean_channel_id(channel_id) when is_binary(channel_id) do
    channel_id
    |> String.trim()
    |> String.trim("\"")
  end

  defp clean_channel_id(channel_id), do: channel_id

  # Process the cleaned channel ID
  defp process_cleaned_channel_id(channel_id) when is_binary(channel_id) and channel_id != "" do
    parse_string_channel_id(channel_id)
  end

  defp process_cleaned_channel_id(channel_id) when is_binary(channel_id) and channel_id == "" do
    Logger.warning("Empty channel ID string", category: :api)
    nil
  end

  defp process_cleaned_channel_id(channel_id) when is_integer(channel_id) do
    Logger.debug("Channel ID is already an integer", channel_id: channel_id, category: :api)
    channel_id
  end

  defp process_cleaned_channel_id(nil) do
    Logger.warning("Channel ID is nil", category: :api)
    nil
  end

  # Validate string channel ID without parsing to integer (avoids overflow)
  defp parse_string_channel_id(channel_id) do
    # Discord IDs are snowflakes (64-bit integers), validate as numeric string
    # without parsing to avoid overflow on large IDs
    if Regex.match?(~r/^\d+$/, channel_id) do
      Logger.debug("Valid numeric channel ID", channel_id: channel_id, category: :api)

      # Keep as string to avoid integer overflow
      channel_id
    else
      Logger.warning("Invalid channel ID format, not numeric",
        channel_id: channel_id,
        category: :api
      )

      nil
    end
  end

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

  @doc """
  Converts any embed format to Nostrum.Struct.Embed.
  """
  def convert_to_nostrum_embed(embed) when is_struct(embed, Embed) do
    # Already a Nostrum embed
    embed
  end

  def convert_to_nostrum_embed(embed) do
    require Logger

    # Convert struct to map if needed
    embed_map =
      if is_struct(embed) do
        Map.from_struct(embed)
      else
        embed
      end

    # Extract fields safely
    fields =
      cond do
        Map.has_key?(embed_map, :fields) -> Map.get(embed_map, :fields)
        Map.has_key?(embed_map, "fields") -> Map.get(embed_map, "fields")
        true -> []
      end

    # Create the Nostrum embed
    discord_embed = %Embed{
      title: get_field_with_fallback(embed_map, :title, "title"),
      description: get_field_with_fallback(embed_map, :description, "description"),
      url: get_field_with_fallback(embed_map, :url, "url"),
      timestamp: get_field_with_fallback(embed_map, :timestamp, "timestamp"),
      color: get_field_with_fallback(embed_map, :color, "color"),
      footer: extract_footer(embed_map),
      image: extract_image(embed_map),
      thumbnail: extract_thumbnail(embed_map),
      author: extract_author(embed_map),
      fields:
        Enum.map(fields, fn field ->
          %Embed.Field{
            name: get_field_with_fallback(field, :name, "name", ""),
            value: get_field_with_fallback(field, :value, "value", ""),
            inline: get_field_with_fallback(field, :inline, "inline", false)
          }
        end)
    }

    discord_embed
  end

  # Extract footer from the embed
  defp extract_footer(embed) do
    footer = get_field_with_fallback(embed, :footer, "footer")

    case footer do
      nil -> nil
      footer_map when is_map(footer_map) -> build_footer(footer_map)
    end
  end

  # Build a footer struct from a map
  defp build_footer(footer_map) do
    %Embed.Footer{
      text: get_field_with_fallback(footer_map, :text, "text", ""),
      icon_url: get_field_with_fallback(footer_map, :icon_url, "icon_url")
    }
  end

  # Extract author from the embed
  defp extract_author(embed) do
    author = get_field_with_fallback(embed, :author, "author")

    case author do
      nil -> nil
      author_map when is_map(author_map) -> build_author(author_map)
    end
  end

  # Build an author struct from a map
  defp build_author(author_map) do
    %Embed.Author{
      name: get_field_with_fallback(author_map, :name, "name", ""),
      url: get_field_with_fallback(author_map, :url, "url"),
      icon_url: get_field_with_fallback(author_map, :icon_url, "icon_url")
    }
  end

  # Get a field with fallback from atom or string keys
  defp get_field_with_fallback(map, atom_key, string_key, default \\ nil) do
    value =
      cond do
        Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
        Map.has_key?(map, string_key) -> Map.get(map, string_key)
        true -> default
      end

    value
  end

  # Extract thumbnail from the embed
  defp extract_thumbnail(embed) do
    thumbnail = get_field_with_fallback(embed, :thumbnail, "thumbnail")
    # Try different formats in order of likelihood
    cond do
      valid_thumbnail = extract_thumbnail_from_map(thumbnail) ->
        valid_thumbnail

      valid_url = extract_valid_url(thumbnail) ->
        %Embed.Thumbnail{url: valid_url}

      valid_url = extract_valid_url(Map.get(embed, "thumbnail_url")) ->
        %Embed.Thumbnail{url: valid_url}

      valid_url = extract_valid_url(Map.get(embed, "icon_url")) ->
        %Embed.Thumbnail{url: valid_url}

      true ->
        extract_thumbnail_from_icon_field(embed)
    end
  end

  # Extract thumbnail from a map with url key
  defp extract_thumbnail_from_map(thumbnail) when is_map(thumbnail) do
    cond do
      valid_url = extract_valid_url(Map.get(thumbnail, :url)) ->
        %Embed.Thumbnail{url: valid_url}

      valid_url = extract_valid_url(Map.get(thumbnail, "url")) ->
        %Embed.Thumbnail{url: valid_url}

      true ->
        nil
    end
  end

  defp extract_thumbnail_from_map(_), do: nil

  # Check for icon field and extract thumbnail
  defp extract_thumbnail_from_icon_field(embed) do
    if Map.has_key?(embed, "icon") do
      icon = Map.get(embed, "icon")

      if is_map(icon) && Map.has_key?(icon, "url") do
        %Embed.Thumbnail{url: icon["url"]}
      else
        nil
      end
    else
      nil
    end
  end

  # Validate URL is not empty
  defp extract_valid_url(url) when is_binary(url) do
    trimmed = String.trim(url)
    if Utils.nil_or_empty?(trimmed), do: nil, else: trimmed
  end

  defp extract_valid_url(_), do: nil

  # Extract image from embed
  defp extract_image(embed) do
    image = get_field_with_fallback(embed, :image, "image")

    case extract_image_from_map(image) do
      {:ok, url} ->
        %Embed.Image{url: url}

      {:error, _} ->
        cond do
          valid_url = extract_valid_url(image) ->
            %Embed.Image{url: valid_url}

          valid_url = extract_valid_url(get_field_with_fallback(embed, :image_url, "image_url")) ->
            %Embed.Image{url: valid_url}

          true ->
            nil
        end
    end
  end

  # Extract image data from a map structure
  defp extract_image_from_map(data) when is_map(data) do
    if Map.has_key?(data, "image") and is_map(data["image"]) and
         Map.has_key?(data["image"], "url") do
      {:ok, data["image"]["url"]}
    else
      {:error, "No image URL found in map"}
    end
  end

  defp extract_image_from_map(_), do: {:error, "Data is not a map"}

  defp get_retry_after(_) do
    5000
  end
end
