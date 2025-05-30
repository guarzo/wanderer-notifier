defmodule WandererNotifier.Notifications.NeoClient do
  @moduledoc """
  Client for sending notifications to Discord via Nostrum.
  """
  require Logger

  def send_embed(embed, channel_id) do
    Logger.info("DEBUG: [NeoClient] Starting send_embed function")
    Logger.info("DEBUG: [NeoClient] Attempting to send embed to channel #{channel_id}")
    Logger.debug("DEBUG: [NeoClient] Embed content: #{inspect(embed, limit: 200)}")

    case validate_inputs(embed, channel_id) do
      :ok ->
        Logger.info("DEBUG: [NeoClient] Input validation passed")
        Logger.info("DEBUG: [NeoClient] Calling Nostrum.Api.Message.create")

        try do
          case Nostrum.Api.Message.create(channel_id, embed: embed) do
            {:ok, response} ->
              Logger.info("DEBUG: [NeoClient] Successfully sent embed to channel #{channel_id}")
              Logger.debug("DEBUG: [NeoClient] Response: #{inspect(response, limit: 200)}")
              :ok

            {:error, error} ->
              error_message = format_error(error)

              Logger.error(
                "DEBUG: [NeoClient] Failed to send embed to channel #{channel_id}: #{error_message}"
              )

              Logger.error("DEBUG: [NeoClient] Error details: #{inspect(error, pretty: true)}")
              Logger.error("DEBUG: [NeoClient] Stack trace: #{Exception.format_stacktrace()}")
              {:error, error}
          end
        rescue
          e ->
            Logger.error(
              "DEBUG: [NeoClient] Exception while sending message: #{Exception.message(e)}"
            )

            Logger.error(
              "DEBUG: [NeoClient] Stack trace: #{Exception.format_stacktrace(__STACKTRACE__)}"
            )

            {:error, e}
        end

      {:error, reason} ->
        Logger.error("DEBUG: [NeoClient] Input validation failed: #{reason}")
        {:error, reason}
    end
  end

  defp validate_inputs(embed, channel_id) do
    Logger.debug(
      "DEBUG: [NeoClient] Validating inputs - embed type: #{inspect(embed.__struct__)}, channel_id: #{inspect(channel_id)}"
    )

    cond do
      is_nil(embed) ->
        {:error, "Embed cannot be nil"}

      is_nil(channel_id) ->
        {:error, "Channel ID cannot be nil"}

      not is_map(embed) ->
        {:error, "Embed must be a map, got: #{inspect(embed)}"}

      not is_integer(channel_id) and not is_binary(channel_id) ->
        {:error, "Channel ID must be an integer or string, got: #{inspect(channel_id)}"}

      true ->
        :ok
    end
  end

  defp format_error(error) do
    case error do
      %{message: message} -> message
      %{reason: reason} -> "Reason: #{reason}"
      error when is_binary(error) -> error
      _ -> inspect(error)
    end
  end
end
