defmodule WandererNotifier.Infrastructure.Adapters.JaniceClient do
  @moduledoc """
  Client for Janice API to get EVE Online item appraisals.

  Janice is a service that provides market pricing for EVE Online items.
  This client handles bulk appraisals for killmail items.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Shared.Config

  @base_url "https://janice.e-351.com"
  @appraisal_endpoint "/api/rest/v2/appraisal"

  # Cache TTL for item prices (6 hours)
  @price_cache_ttl :timer.hours(6)

  @doc """
  Check if Janice API is enabled (token is configured).
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Config.get(:janice_api_token) != nil
  end

  @doc """
  Appraise a list of items and return their values.

  Items should be in the format:
  ```
  [
    %{"type_id" => 12345, "quantity" => 1},
    %{"type_id" => 67890, "quantity" => 5}
  ]
  ```

  Returns:
  ```
  {:ok, %{
    "12345" => %{"name" => "Item Name", "price" => 1000000.0},
    "67890" => %{"name" => "Other Item", "price" => 500000.0}
  }}
  ```
  """
  @spec appraise_items(list(map())) :: {:ok, map()} | {:error, term()}
  def appraise_items(items) when is_list(items) do
    if enabled?() do
      do_appraise_items(items)
    else
      {:error, :janice_not_configured}
    end
  end

  defp do_appraise_items(items) do
    {cached_items, uncached_items} = split_cached_items(items)

    case uncached_items do
      [] -> {:ok, cached_items}
      uncached -> fetch_and_merge_items(cached_items, uncached)
    end
  end

  defp fetch_and_merge_items(cached_items, uncached_items) do
    case fetch_appraisal(uncached_items) do
      {:ok, new_prices} ->
        cache_prices(new_prices)
        {:ok, Map.merge(cached_items, new_prices)}

      {:error, reason} = error ->
        Logger.warning("Janice API error", reason: reason, category: :janice)
        error
    end
  end

  @doc """
  Format items for Janice API request.

  Converts our internal format to Janice's expected format.
  """
  @spec format_appraisal_request(list(map())) :: String.t()
  def format_appraisal_request(items) do
    items
    |> Enum.filter(fn item ->
      # Use name if available, otherwise fall back to type_id
      name_or_id =
        Map.get(item, "name") || Map.get(item, "type_id") || Map.get(item, "item_type_id")

      quantity = Map.get(item, "quantity", 1)
      # Filter out invalid items
      not is_nil(name_or_id) and name_or_id != "" and quantity > 0
    end)
    |> Enum.map(fn item ->
      # Prefer name over type_id for Janice API
      name_or_id =
        Map.get(item, "name") || Map.get(item, "type_id") || Map.get(item, "item_type_id")

      quantity = Map.get(item, "quantity", 1)
      "#{name_or_id} #{quantity}"
    end)
    |> Enum.join("\n")
  end

  # Private functions

  defp split_cached_items(items) do
    items
    |> Enum.reduce({%{}, []}, fn item, {cached, uncached} ->
      type_id = to_string(Map.get(item, "type_id") || Map.get(item, "item_type_id"))

      case get_cached_price(type_id) do
        {:ok, price_data} ->
          {Map.put(cached, type_id, price_data), uncached}

        :error ->
          {cached, [item | uncached]}
      end
    end)
  end

  defp get_cached_price(type_id) do
    cache_key = "janice:item:#{type_id}"

    case Cache.get(cache_key) do
      {:ok, price_data} -> {:ok, price_data}
      _ -> :error
    end
  end

  defp cache_prices(prices) do
    Enum.each(prices, fn {type_id, price_data} ->
      cache_key = "janice:item:#{type_id}"
      Cache.put(cache_key, price_data, @price_cache_ttl)
    end)
  end

  defp fetch_appraisal(items) do
    request_config = build_request_config(items)
    execute_request(request_config)
  end

  defp build_request_config(items) do
    url = build_request_url()
    body = build_request_body(items)
    headers = build_request_headers()

    %{
      url: url,
      body: body,
      headers: headers,
      original_item_count: length(items)
    }
  end

  defp build_request_url do
    url = @base_url <> @appraisal_endpoint

    params = %{
      # Jita
      "market" => "2",
      "designation" => "appraisal",
      "pricing" => "buy",
      "pricingVariant" => "immediate",
      "persist" => "true",
      "compactize" => "true",
      "pricePercentage" => "1"
    }

    query_string = URI.encode_query(params)
    "#{url}?#{query_string}"
  end

  defp build_request_body(items) do
    body = format_appraisal_request(items)
    Logger.debug("Processing #{length(items)} items for appraisal")
    body
  end

  defp build_request_headers do
    api_token = Config.get(:janice_api_token)
    Logger.debug("API token length: #{if api_token, do: String.length(api_token), else: "nil"}")

    [
      {"Content-Type", "text/plain"},
      # Note: lowercase 'k' in Apikey
      {"X-Apikey", "#{api_token}"}
    ]
  end

  defp execute_request(config) do
    log_request_details(config)

    case WandererNotifier.Infrastructure.Http.request(
           :post,
           config.url,
           config.headers,
           config.body,
           timeout: 20_000
         ) do
      {:ok, response} -> handle_response(response)
      {:error, reason} -> handle_request_error(reason)
    end
  end

  defp log_request_details(%{url: url, body: body, headers: headers, original_item_count: count}) do
    Logger.debug("Requesting Janice appraisal - Items: #{count}, URL: #{url}")
    Logger.debug("Janice request body preview: #{String.slice(body, 0, 100)}")
    Logger.debug("Janice request body full: #{body}")
    Logger.debug("Janice request headers: #{inspect(headers)}")
  end

  defp handle_response(%Req.Response{status: 200, body: response}) do
    parse_appraisal_response(response)
  end

  defp handle_response(%Req.Response{status: 401}) do
    Logger.warning("Janice API authentication failed - check JANICE_API_TOKEN")
    {:error, :unauthorized}
  end

  defp handle_response(%Req.Response{status: 429}) do
    Logger.warning("Janice API rate limited")
    {:error, :rate_limited}
  end

  defp handle_response(%Req.Response{status: status, body: body}) do
    Logger.warning("Janice API error - HTTP #{status} - Body: #{inspect(body)}")
    {:error, %{status: status, body: body}}
  end

  defp handle_request_error(reason) do
    Logger.warning("Janice HTTP request failed - Reason: #{inspect(reason)}")
    {:error, reason}
  end

  defp parse_appraisal_response(%{"items" => items, "failures" => failures})
       when is_list(items) do
    if failures != "" do
      Logger.warning("Janice API: Some items failed to process",
        failures: failures,
        successful_items: length(items),
        category: :janice
      )
    end

    if items == [] do
      Logger.warning(
        "Janice API: No items were successfully processed. Items need to be item names, not type IDs",
        category: :janice
      )

      {:error, :no_items_processed}
    else
      Logger.debug("Parsing Janice response",
        item_count: length(items),
        category: :janice
      )

      parsed_items =
        items
        |> Enum.map(fn item ->
          # The structure might be different based on the actual response
          type_id = to_string(item["itemType"]["eid"])

          price_data = %{
            "name" => item["itemType"]["name"],
            "price" => get_in(item, ["immediatePrices", "buyPrice"]) || 0,
            "volume" => item["itemType"]["volume"] || 0
          }

          {type_id, price_data}
        end)
        |> Map.new()

      {:ok, parsed_items}
    end
  end

  defp parse_appraisal_response(response) do
    Logger.error(
      "Unexpected Janice response format - Response: #{inspect(response, limit: :infinity)}"
    )

    {:error, :invalid_response}
  end
end
