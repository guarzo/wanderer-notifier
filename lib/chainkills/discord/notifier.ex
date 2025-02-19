defmodule ChainKills.Discord.Notifier do
  @moduledoc """
  Discord notifier using Nostrum. Single channel approach.
  """
  require Logger
  alias Nostrum.Api

  def send_message(msg) do
    channel_id = get_channel_id()
    do_send_message(channel_id, msg)
  end

  def close do
    Logger.info("[Discord] Closing session")
    :ok
  end

  defp get_channel_id do
    case Application.get_env(:chainkills, :discord_channel_id) do
      int when is_integer(int) ->
        int

      bin when is_binary(bin) ->
        String.to_integer(bin)

      other ->
        raise "Invalid or missing :discord_channel_id (got: #{inspect(other)})"
    end
  end

  defp do_send_message(channel_id, msg) do
    final_message = if is_binary(msg), do: msg, else: inspect(msg)
    Logger.info("[Discord] Sending: #{final_message}")

    case Api.create_message(channel_id, final_message) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send Discord message: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
