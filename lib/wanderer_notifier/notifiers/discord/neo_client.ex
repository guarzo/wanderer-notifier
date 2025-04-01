defmodule WandererNotifier.Notifiers.Discord.NeoClient do
  @moduledoc """
  Nostrum-based Discord client implementation.
  Leverages the Nostrum library for interaction with Discord API and event handling.
  """
  use Nostrum.Consumer

  alias Nostrum.Api.Message
  alias Nostrum.Struct.Embed
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @doc """
  Gets the configured Discord channel ID as an integer.
  """
  def channel_id do
    config = Notifications.get_discord_config()
    # Convert the channel id from string to integer
    config.main_channel |> String.to_integer()
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
      AppLogger.api_info("TEST MODE: Would send embed to Discord via Nostrum",
        embed: inspect(embed)
      )

      :ok
    else
      target_channel =
        if is_nil(override_channel_id) do
          channel_id()
        else
          override_channel_id
        end

      # Convert to Nostrum.Struct.Embed
      discord_embed = convert_to_nostrum_embed(embed)

      # Use Nostrum.Api.Message.create with embeds (plural) as an array
      # This is what Discord API expects
      case Message.create(target_channel, embeds: [discord_embed]) do
        {:ok, _message} ->
          :ok

        {:error, %{status_code: 429, response: response}} ->
          retry_after = get_retry_after(response)
          AppLogger.api_error("Discord rate limit hit via Nostrum", retry_after: retry_after)
          {:error, {:rate_limited, retry_after}}

        {:error, error} ->
          AppLogger.api_error("Failed to send embed via Nostrum", error: inspect(error))
          {:error, error}
      end
    end
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
      AppLogger.api_info("TEST MODE: Would send message with components via Nostrum",
        embed: inspect(embed),
        components: inspect(components)
      )

      :ok
    else
      target_channel =
        if is_nil(override_channel_id) do
          channel_id()
        else
          override_channel_id
        end

      # Convert to Nostrum structs
      discord_embed = convert_to_nostrum_embed(embed)
      discord_components = components

      # Log detailed info about what we're sending
      AppLogger.api_debug("Sending message with components via Nostrum",
        channel_id: target_channel,
        embed_type: typeof(discord_embed)
      )

      case Message.create(target_channel,
             embeds: [discord_embed],
             components: discord_components
           ) do
        {:ok, _message} ->
          :ok

        {:error, %{status_code: 429, response: response}} ->
          retry_after = get_retry_after(response)
          AppLogger.api_error("Discord rate limit hit via Nostrum", retry_after: retry_after)
          {:error, {:rate_limited, retry_after}}

        {:error, error} ->
          AppLogger.api_error("Failed to send message with components via Nostrum",
            error: inspect(error)
          )

          {:error, error}
      end
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
      AppLogger.api_info("TEST MODE: Would send message via Nostrum", message: message)
      :ok
    else
      target_channel =
        if is_nil(override_channel_id) do
          channel_id()
        else
          override_channel_id
        end

      AppLogger.api_debug("Sending text message via Nostrum",
        channel_id: target_channel,
        message_length: String.length(message)
      )

      case Message.create(target_channel, content: message) do
        {:ok, _message} ->
          :ok

        {:error, %{status_code: 429, response: response}} ->
          retry_after = get_retry_after(response)
          AppLogger.api_error("Discord rate limit hit via Nostrum", retry_after: retry_after)
          {:error, {:rate_limited, retry_after}}

        {:error, error} ->
          AppLogger.api_error("Failed to send message via Nostrum", error: inspect(error))
          {:error, error}
      end
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

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_file(filename, file_data, title \\ nil, description \\ nil, override_channel_id \\ nil) do
    AppLogger.api_info("Sending file to Discord via Nostrum", filename: filename)

    if env() == :test do
      log_test_file_send(filename, title)
    else
      send_real_file(filename, file_data, title, description, override_channel_id)
    end
  end

  defp log_test_file_send(filename, title) do
    AppLogger.api_info("TEST MODE: Would send file to Discord via Nostrum",
      filename: filename,
      title: title || "No title"
    )

    :ok
  end

  defp send_real_file(filename, file_data, title, description, override_channel_id) do
    target_channel =
      if is_nil(override_channel_id) do
        channel_id()
      else
        override_channel_id
      end

    embed_opts = create_file_embed_opts(title, description, filename)
    file = %{name: filename, body: file_data}

    do_send_file(target_channel, file, embed_opts)
  end

  defp create_file_embed_opts(title, description, filename) do
    if title || description do
      discord_embed = %Embed{
        title: title || filename,
        description: description || "",
        color: 3_447_003,
        timestamp: DateTime.utc_now(),
        footer: %Embed.Footer{
          text: "Generated by WandererNotifier"
        }
      }

      # Use embeds (plural) not embed (singular) for Discord API
      [embeds: [discord_embed]]
    else
      []
    end
  end

  defp do_send_file(target_channel, file, embed_opts) do
    options =
      if Enum.empty?(embed_opts) do
        [file: file]
      else
        # For direct file uploads with embed, ensure we're using the proper format
        if Keyword.has_key?(embed_opts, :embed) do
          # Convert embed to embeds format
          embed = Keyword.get(embed_opts, :embed)
          [file: file, embeds: [embed]]
        else
          # Keep as is if already using embeds format
          [file: file] ++ embed_opts
        end
      end

    AppLogger.api_debug("Sending file via Nostrum",
      channel_id: target_channel,
      options: inspect(options)
    )

    case Message.create(target_channel, options) do
      {:ok, _message} ->
        :ok

      {:error, %{status_code: 429, response: response}} ->
        retry_after = get_retry_after(response)
        AppLogger.api_error("Discord rate limit hit via Nostrum", retry_after: retry_after)
        {:error, {:rate_limited, retry_after}}

      {:error, error} ->
        AppLogger.api_error("Failed to send file via Nostrum", error: inspect(error))
        {:error, error}
    end
  end

  # -- EVENT HANDLING --

  @doc """
  Handle interaction events from Discord.
  This allows responding to button clicks, select menu choices, etc.
  """
  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    AppLogger.api_info("Received Discord interaction",
      type: interaction.type,
      guild_id: interaction.guild_id,
      channel_id: interaction.channel_id
    )

    :noop
  end

  @impl true
  def handle_event(_event) do
    :noop
  end

  # -- HELPERS --

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

  defp convert_to_nostrum_embed(embed) when is_map(embed) do
    %Embed{
      title: Map.get(embed, "title"),
      description: Map.get(embed, "description"),
      url: Map.get(embed, "url"),
      timestamp: Map.get(embed, "timestamp"),
      color: Map.get(embed, "color"),
      footer: extract_footer(embed),
      image: extract_image(embed),
      thumbnail: get_thumbnail_with_fallback(embed),
      author: extract_author(embed),
      fields: extract_fields(embed)
    }
  end

  # Extract fields from the embed
  defp extract_fields(embed) do
    Map.get(embed, "fields", [])
    |> Enum.map(fn field ->
      %Embed.Field{
        name: Map.get(field, "name", ""),
        value: Map.get(field, "value", ""),
        inline: Map.get(field, "inline", false)
      }
    end)
  end

  # Extract footer from the embed
  defp extract_footer(embed) do
    case Map.get(embed, "footer") do
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
    case Map.get(embed, "author") do
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
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  # Apply system notification thumbnail fallback if needed
  defp get_thumbnail_with_fallback(embed) do
    thumbnail = extract_thumbnail(embed)

    # If this is a sun type notification with no thumbnail, use a hardcoded URL
    if is_nil(thumbnail) && Map.get(embed, "title", "") =~ "System Notification" do
      %Embed.Thumbnail{url: "https://images.evetech.net/types/45041/icon?size=64"}
    else
      thumbnail
    end
  end

  # Extract thumbnail from the embed
  defp extract_thumbnail(embed) do
    thumbnail = Map.get(embed, "thumbnail")

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
    if trimmed != "", do: trimmed, else: nil
  end

  defp extract_valid_url(_), do: nil

  # Extract image from embed
  defp extract_image(embed) do
    image = Map.get(embed, "image")

    # Try different formats in order of likelihood
    cond do
      valid_image = extract_image_from_map(image) -> valid_image
      valid_url = extract_valid_url(image) -> %Embed.Image{url: valid_url}
      valid_url = extract_valid_url(Map.get(embed, "image_url")) -> %Embed.Image{url: valid_url}
      true -> nil
    end
  end

  # Extract image from a map with url key
  defp extract_image_from_map(image) when is_map(image) do
    cond do
      valid_url = extract_valid_url(Map.get(image, :url)) ->
        %Embed.Image{url: valid_url}

      valid_url = extract_valid_url(Map.get(image, "url")) ->
        %Embed.Image{url: valid_url}

      true ->
        nil
    end
  end

  defp extract_image_from_map(_), do: nil

  defp get_retry_after(%{"retry_after" => retry_after}) when is_number(retry_after) do
    round(retry_after * 1000)
  end

  defp get_retry_after(%{"retry_after" => retry_after}) when is_binary(retry_after) do
    case Float.parse(retry_after) do
      {value, _} -> round(value * 1000)
      :error -> 5000
    end
  end

  defp get_retry_after(_) do
    5000
  end
end
