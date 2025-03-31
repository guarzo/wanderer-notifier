defmodule WandererNotifier.Discord.NeoClient do
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
  Gets the configured Discord channel ID.
  """
  def channel_id do
    config = Notifications.get_discord_config()
    config.main_channel
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
      target_channel = if is_nil(override_channel_id), do: channel_id(), else: override_channel_id

      # Convert to Nostrum.Struct.Embed
      discord_embed = convert_to_nostrum_embed(embed)

      # Send using Nostrum's API
      AppLogger.api_debug("Calling Nostrum.Api.Message.create with embed",
        channel_id: target_channel,
        embed_type: typeof(discord_embed)
      )

      # Use explicit keyword list with square brackets - SUPER IMPORTANT
      # Nostrum expects `[embeds: [...]]` not `%{embeds: [...]}`
      case Message.create(target_channel, [embeds: [discord_embed]]) do
        {:ok, _message} ->
          AppLogger.api_info("Successfully sent embed via Nostrum")
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
      target_channel = if is_nil(override_channel_id), do: channel_id(), else: override_channel_id

      # Convert to Nostrum structs
      discord_embed = convert_to_nostrum_embed(embed)
      discord_components = components

      # Send using Nostrum's API
      AppLogger.api_debug("Calling Nostrum.Api.Message.create with embed and components",
        channel_id: target_channel
      )

      # Use explicit keyword list with square brackets
      case Message.create(target_channel,
             [embeds: [discord_embed],
             components: discord_components
           ]) do
        {:ok, _message} ->
          AppLogger.api_info("Successfully sent message with components via Nostrum")
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
      target_channel = if is_nil(override_channel_id), do: channel_id(), else: override_channel_id

      # IMPORTANT: Use a proper keyword list with content key
      # Nostrum 0.10.4 expects [content: message], not a string
      AppLogger.api_debug("Calling Nostrum.Api.Message.create",
        channel_id: target_channel,
        message: message
      )

      # Use explicit keyword list with square brackets
      case Message.create(target_channel, [content: message]) do
        {:ok, _message} ->
          AppLogger.api_info("Successfully sent message via Nostrum")
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

  # Log a test file send operation (no actual API call)
  defp log_test_file_send(filename, title) do
    AppLogger.api_info("TEST MODE: Would send file to Discord via Nostrum",
      filename: filename,
      title: title || "No title"
    )

    :ok
  end

  # Send a real file to Discord
  defp send_real_file(filename, file_data, title, description, override_channel_id) do
    target_channel = if is_nil(override_channel_id), do: channel_id(), else: override_channel_id

    # Create embed options if title/description provided
    embed_opts = create_file_embed_opts(title, description, filename)

    # Prepare file
    file = %{name: filename, body: file_data}

    # Send the file
    do_send_file(target_channel, file, embed_opts)
  end

  # Create embed options for file uploads
  defp create_file_embed_opts(title, description, filename) do
    if title || description do
      discord_embed = %Embed{
        title: title || filename,
        description: description || "",
        # Discord blue
        color: 3_447_003,
        timestamp: DateTime.utc_now(),
        footer: %Embed.Footer{
          text: "Generated by WandererNotifier"
        }
      }

      [embed: discord_embed]
    else
      []
    end
  end

  # Actually send the file to Discord
  defp do_send_file(target_channel, file, embed_opts) do
    # Prepare options as a keyword list with square brackets
    file_opts = [files: [file]]

    # If embed options are provided, add them to the keyword list
    options =
      if Enum.empty?(embed_opts), do: file_opts, else: Keyword.merge(file_opts, embed_opts)

    # Log the operation
    AppLogger.api_debug("Calling Nostrum.Api.Message.create with file",
      channel_id: target_channel,
      options: inspect(options)
    )

    # Use explicit keyword list
    case Message.create(target_channel, options) do
      {:ok, _message} ->
        AppLogger.api_info("Successfully sent file via Nostrum")
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

    # Log the interaction but don't handle it yet
    # Future implementation would process button clicks, etc.
    :noop
  end

  # Ignore other event types for now
  @impl true
  def handle_event(_event) do
    :noop
  end

  # -- HELPERS --

  # Helper function to determine the type of a term (for debugging)
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

  # Convert a raw embed map to Nostrum.Struct.Embed
  defp convert_to_nostrum_embed(embed) when is_map(embed) do
    fields =
      Map.get(embed, "fields", [])
      |> Enum.map(fn field ->
        %Embed.Field{
          name: Map.get(field, "name", ""),
          value: Map.get(field, "value", ""),
          inline: Map.get(field, "inline", false)
        }
      end)

    footer =
      case Map.get(embed, "footer") do
        nil ->
          nil

        footer_map ->
          %Embed.Footer{
            text: Map.get(footer_map, "text", ""),
            icon_url: Map.get(footer_map, "icon_url")
          }
      end

    thumbnail =
      case Map.get(embed, "thumbnail") do
        nil -> nil
        thumb_map -> %Embed.Thumbnail{url: Map.get(thumb_map, "url", "")}
      end

    image =
      case Map.get(embed, "image") do
        nil -> nil
        image_map -> %Embed.Image{url: Map.get(image_map, "url", "")}
      end

    author =
      case Map.get(embed, "author") do
        nil ->
          nil

        author_map ->
          %Embed.Author{
            name: Map.get(author_map, "name", ""),
            url: Map.get(author_map, "url"),
            icon_url: Map.get(author_map, "icon_url")
          }
      end

    %Embed{
      title: Map.get(embed, "title"),
      description: Map.get(embed, "description"),
      url: Map.get(embed, "url"),
      timestamp: Map.get(embed, "timestamp"),
      color: Map.get(embed, "color"),
      footer: footer,
      image: image,
      thumbnail: thumbnail,
      author: author,
      fields: fields
    }
  end

  # Extract retry_after from rate limit response
  defp get_retry_after(%{"retry_after" => retry_after}) when is_number(retry_after) do
    # Convert to milliseconds
    round(retry_after * 1000)
  end

  defp get_retry_after(%{"retry_after" => retry_after}) when is_binary(retry_after) do
    # Convert string to float then to milliseconds
    case Float.parse(retry_after) do
      {value, _} -> round(value * 1000)
      # Default if parsing fails
      :error -> 5000
    end
  end

  defp get_retry_after(_) do
    # Default retry time
    5000
  end
end
