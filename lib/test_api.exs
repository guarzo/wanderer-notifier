# Test script to check the characters API endpoint
# Run this script with: mix run lib/test_api.exs

alias WandererNotifier.Api.Http.Client
alias WandererNotifier.Api.Map.UrlBuilder
alias WandererNotifier.Core.Config

defmodule TestApi do
  def run do
    IO.puts("Testing Characters API endpoint")

    log_environment()
    log_config_values()

    # Build URL and make request
    case build_url_and_get_headers() do
      {:ok, url, headers} ->
        make_request_and_handle_response(url, headers)

      {:error, reason} ->
        IO.puts("\nURL builder error: #{inspect(reason)}")
    end
  end

  # Log environment variables
  defp log_environment do
    IO.puts("Environment variables:")
    IO.puts("MAP_URL: #{System.get_env("MAP_URL")}")
    IO.puts("MAP_NAME: #{System.get_env("MAP_NAME")}")
    IO.puts("MAP_TOKEN: #{(System.get_env("MAP_TOKEN") && "PRESENT") || "MISSING"}")
  end

  # Log config values
  defp log_config_values do
    IO.puts("\nConfig values:")
    IO.puts("map_url: #{Config.map_url()}")
    IO.puts("map_name: #{Config.map_name()}")
    IO.puts("map_token: #{(Config.map_token() && "PRESENT") || "MISSING"}")
  end

  # Build URL and get headers
  defp build_url_and_get_headers do
    IO.puts("\nBuilding URL:")

    case UrlBuilder.build_url("map/characters") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()
        IO.puts("Headers: #{inspect(headers)}")
        {:ok, url, headers}

      error ->
        IO.puts("URL result: #{inspect(error)}")
        error
    end
  end

  # Make request and handle response
  defp make_request_and_handle_response(url, headers) do
    IO.puts("\nMaking request to URL: #{url}")
    response = Client.get(url, headers)
    IO.puts("\nResponse: #{inspect(response)}")

    handle_response(response)
  end

  # Handle the API response
  defp handle_response({:ok, %{status_code: 200, body: body}} = _response) when is_binary(body) do
    IO.puts("\nSuccessful response!")
    IO.puts("Body preview: #{String.slice(body, 0, 100)}...")

    parse_response_body(body)
  end

  defp handle_response({:ok, resp}) do
    IO.puts("\nNon-success response: #{inspect(resp)}")
  end

  defp handle_response({:error, reason}) do
    IO.puts("\nRequest error: #{inspect(reason)}")
  end

  # Parse response body
  defp parse_response_body(body) do
    case Jason.decode(body) do
      {:ok, parsed} ->
        IO.puts("\nJSON parsed successfully")
        IO.puts("Data preview: #{inspect(parsed)}")

      {:error, error} ->
        IO.puts("\nJSON parsing error: #{inspect(error)}")
    end
  end
end

# Run the test
TestApi.run()
