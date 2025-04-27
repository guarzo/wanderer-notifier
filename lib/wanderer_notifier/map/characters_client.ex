defmodule WandererNotifier.Map.CharactersClient do
  @moduledoc """
  Client for interacting with character data in the Map API
  """

  require Logger
  alias WandererNotifier.Api.Map.Characters
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Config.Config

  @doc """
  Updates the tracked characters

  This function can either:
  - Be called with a list of characters to process directly
  - Be called with no arguments to fetch characters from the API
  - Be called with a raw response body to parse

  Returns {:ok, characters} on success, {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ nil)

  def update_tracked_characters(characters) when is_list(characters) do
    Logger.info("Updating tracked characters", %{count: length(characters)})
    Characters.update_tracked_characters(characters)
  end

  def update_tracked_characters(raw_body) when is_binary(raw_body) do
    Logger.info("Processing raw character data", %{data_length: String.length(raw_body)})
    Characters.update_tracked_characters(raw_body, nil)
  end

  def update_tracked_characters(nil) do
    Logger.info("Fetching and updating tracked characters")
    Characters.update_tracked_characters()
  end

  @doc """
  Checks availability of the characters endpoint

  Returns {:ok, true} if available, {:error, reason} if not
  """
  def check_endpoint_availability do
    Characters.check_characters_endpoint_availability()
  end

  @doc """
  Gets character activity

  Returns {:ok, activity_data} on success, {:error, reason} on failure
  """
  def get_character_activity(slug) do
    Logger.info("Getting character activity", %{slug: slug})

    # Build the URL for the activity endpoint
    activity_url = build_activity_url(slug)
    headers = build_headers()

    # Make the request
    case HttpClient.get(activity_url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status_code: status_code}} ->
        {:error, "Failed to get character activity: HTTP #{status_code}"}

      {:error, reason} ->
        {:error, "Failed to get character activity: #{inspect(reason)}"}
    end
  end

  # Private helper functions

  defp build_activity_url(slug) do
    base_url = Config.map_url()
    uri = URI.parse(base_url)
    base_host = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

    "#{base_host}/api/map/character_activity?slug=#{URI.encode_www_form(slug)}"
  end

  defp build_headers do
    map_token = Config.map_token()

    [
      {"Authorization", "Bearer #{map_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end
end
