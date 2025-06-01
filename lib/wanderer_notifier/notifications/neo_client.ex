defmodule WandererNotifier.Notifications.NeoClient do
  @moduledoc """
  Client for sending notifications to Discord via Nostrum.
  """
  require Logger

  alias Nostrum.Api.Message

  def send_embed(embed, channel_id) do
    case validate_inputs(embed, channel_id) do
      :ok ->
        try do
          case Message.create(channel_id, embed: embed) do
            {:ok, _response} ->
              :ok

            {:error, error} ->
              error_message = format_error(error)
              Logger.error("Failed to send embed to channel #{channel_id}: #{error_message}")
              {:error, error}
          end
        rescue
          e ->
            Logger.error("Exception while sending message: #{Exception.message(e)}")
            {:error, e}
        end

      {:error, reason} ->
        Logger.error("Input validation failed: #{reason}")
        {:error, reason}
    end
  end

  defp validate_inputs(nil, _channel_id), do: {:error, "Embed cannot be nil"}
  defp validate_inputs(_embed, nil), do: {:error, "Channel ID cannot be nil"}

  defp validate_inputs(embed, _channel_id) when not is_map(embed),
    do: {:error, "Embed must be a map, got: #{inspect(embed)}"}

  defp validate_inputs(_embed, channel_id)
       when not is_integer(channel_id) and not is_binary(channel_id),
       do: {:error, "Channel ID must be an integer or string, got: #{inspect(channel_id)}"}

  defp validate_inputs(_embed, _channel_id), do: :ok

  defp format_error(error) do
    case error do
      %{message: message} -> message
      %{reason: reason} -> "Reason: #{reason}"
      error when is_binary(error) -> error
      _ -> inspect(error)
    end
  end
end
