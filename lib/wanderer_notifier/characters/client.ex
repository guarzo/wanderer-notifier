defmodule WandererNotifier.Characters.Client do
  @moduledoc """
  Client for interacting with the characters API.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  def fetch_characters(slug) do
    url = "https://wanderer.zoolanders.space/api/map/user_characters?slug=#{slug}"

    case HTTPoison.get(url) do
      response -> handle_characters_response(response)
    end
  end

  defp handle_characters_response({:ok, %{status_code: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, data} ->
        AppLogger.api_info("Extracting characters from API response with #{length(data)} groups",
          category: :api
        )

        characters =
          data
          |> Enum.flat_map(fn group ->
            case group do
              %{"characters" => chars} when is_list(chars) -> chars
              _ -> []
            end
          end)
          |> Enum.map(&extract_character_info/1)
          |> Enum.reject(&is_nil/1)

        total_count = length(characters)
        new_count = update_tracked_characters(characters)

        AppLogger.api_info("[CharactersClient] Character update completed successfully",
          category: :api,
          new_count: new_count,
          total_count: total_count
        )

        {:ok, characters}

      {:error, reason} ->
        AppLogger.api_error("Failed to decode characters API response",
          category: :api,
          error: inspect(reason)
        )

        {:error, :invalid_response}
    end
  end

  defp handle_characters_response({:error, reason}) do
    AppLogger.api_error("Failed to fetch characters from API",
      category: :api,
      error: inspect(reason)
    )

    {:error, :request_failed}
  end

  defp extract_character_info(%{"character_id" => id, "name" => name}) do
    %{
      id: id,
      name: name
    }
  end

  defp extract_character_info(_), do: nil

  defp update_tracked_characters(characters) do
    # TODO: Implement actual character tracking logic
    # For now, just return the count of characters
    length(characters)
  end
end
