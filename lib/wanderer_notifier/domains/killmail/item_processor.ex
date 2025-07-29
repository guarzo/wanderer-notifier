defmodule WandererNotifier.Domains.Killmail.ItemProcessor do
  @moduledoc """
  Process killmail items to identify and enrich notable items.

  Notable items are defined as:
  - Items containing "abyssal" in the name (case insensitive)
  - Items worth more than the configured threshold (default 50M ISK)

  This module automatically checks if Janice API is configured and gracefully
  handles cases where it's not available.
  """

  require Logger
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Infrastructure.Adapters.JaniceClient
  alias WandererNotifier.Infrastructure.Adapters.ESI.Service, as: ESIService
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Shared.Config

  # Helper function for safe integer parsing
  defp safe_parse_killmail_id(killmail_id_str) when is_binary(killmail_id_str) do
    case Integer.parse(killmail_id_str) do
      {int_id, ""} -> {:ok, int_id}
      {_int_id, _remainder} -> {:error, :invalid_format}
      :error -> {:error, :invalid_format}
    end
  end

  defp safe_parse_killmail_id(killmail_id) when is_integer(killmail_id), do: {:ok, killmail_id}
  defp safe_parse_killmail_id(_), do: {:error, :invalid_format}

  # Helper function to get type names with caching
  defp get_type_names_cached(type_ids) do
    # Try to get cached names first
    cached_names =
      type_ids
      |> Enum.map(fn type_id ->
        case Cache.get_universe_type(type_id) do
          {:ok, type_data} -> {to_string(type_id), Map.get(type_data, "name", "Unknown Item")}
          {:error, :not_found} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Map.new()

    # Find missing type IDs
    missing_type_ids =
      type_ids
      |> Enum.filter(fn type_id ->
        not Map.has_key?(cached_names, to_string(type_id))
      end)

    # Fetch missing names from ESI
    case missing_type_ids do
      [] ->
        {:ok, cached_names}

      missing_ids ->
        {:ok, fetched_names} = ESIService.get_type_names(missing_ids)

        # Cache the new names
        fetched_names
        |> Enum.each(fn {type_id_str, name} ->
          type_id = String.to_integer(type_id_str)
          type_data = %{"name" => name}
          Cache.put_universe_type(type_id, type_data)
        end)

        # Merge cached and fetched names
        all_names = Map.merge(cached_names, fetched_names)
        {:ok, all_names}
    end
  end

  # Helper function to get Janice prices with caching
  defp get_janice_prices_cached(items) do
    # Create a cache key based on the items (simplified - using type_ids and quantities)
    cache_key_data =
      items
      |> Enum.map(fn item ->
        type_id = Map.get(item, "type_id") || Map.get(item, "item_type_id")
        quantity = Map.get(item, "quantity", 1)
        {type_id, quantity}
      end)
      |> Enum.sort()

    cache_key = "janice_appraisal:#{:erlang.phash2(cache_key_data)}"

    # Try to get cached prices first
    case Cache.get(cache_key) do
      {:ok, cached_prices} ->
        Logger.debug("Using cached Janice prices")
        {:ok, cached_prices}

      {:error, :not_found} ->
        # Fetch fresh prices from Janice
        case JaniceClient.appraise_items(items) do
          {:ok, price_data} ->
            # Cache the results with item price TTL
            Cache.put(cache_key, price_data, Cache.item_price_ttl())
            {:ok, price_data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Check if item processing is enabled (Janice API token is configured).
  """
  @spec enabled?() :: boolean()
  def enabled? do
    JaniceClient.enabled?()
  end

  @doc """
  Process killmail items to identify and enrich notable items.

  Returns the killmail with enriched item data if processing is enabled,
  otherwise returns the killmail unchanged.
  """
  @spec process_killmail_items(Killmail.t()) :: {:ok, Killmail.t()} | {:error, term()}
  def process_killmail_items(%Killmail{} = killmail) do
    if enabled?() do
      do_process_items(killmail)
    else
      Logger.debug("Item processing disabled - no Janice API token configured")
      {:ok, killmail}
    end
  end

  # Private functions

  defp do_process_items(%Killmail{} = killmail) do
    log_processing_start(killmail)

    with {:ok, items_dropped} <- extract_dropped_items(killmail),
         {:ok, notable_items} <- identify_and_enrich_notable_items(items_dropped) do
      enriched_killmail = build_enriched_killmail(killmail, items_dropped, notable_items)
      log_processing_success(killmail, items_dropped, notable_items)
      {:ok, enriched_killmail}
    else
      {:error, reason} = error ->
        log_processing_failure(killmail, reason)
        error
    end
  end

  defp log_processing_start(killmail) do
    Logger.debug("Processing killmail items - full structure",
      killmail_id: killmail.killmail_id,
      has_esi_data: killmail.esi_data != nil,
      esi_data_keys: get_esi_data_keys(killmail.esi_data),
      full_killmail_struct: inspect(killmail, limit: :infinity),
      category: :item_processing
    )
  end

  defp get_esi_data_keys(nil), do: nil
  defp get_esi_data_keys(esi_data), do: Map.keys(esi_data)

  defp build_enriched_killmail(killmail, items_dropped, notable_items) do
    %{killmail | items_dropped: items_dropped, notable_items: notable_items}
  end

  defp log_processing_success(killmail, items_dropped, notable_items) do
    Logger.debug("Item processing completed",
      killmail_id: killmail.killmail_id,
      total_items: length(items_dropped),
      notable_items: length(notable_items),
      category: :item_processing
    )
  end

  defp log_processing_failure(killmail, reason) do
    Logger.warning("Item processing failed",
      killmail_id: killmail.killmail_id,
      reason: reason,
      category: :item_processing
    )
  end

  defp extract_dropped_items(%Killmail{esi_data: nil} = killmail) do
    Logger.debug("No ESI data available, attempting to fetch from ESI API",
      killmail_id: killmail.killmail_id,
      category: :item_processing
    )

    # Try to fetch the killmail from ESI API directly
    case get_killmail_hash_from_killmail(killmail) do
      nil ->
        Logger.debug("No killmail hash available, cannot fetch from ESI",
          killmail_id: killmail.killmail_id,
          category: :item_processing
        )

        {:ok, []}

      killmail_hash ->
        case safe_parse_killmail_id(killmail.killmail_id) do
          {:ok, killmail_id_int} ->
            case ESIService.get_killmail(killmail_id_int, killmail_hash) do
              {:ok, esi_killmail} ->
                esi_killmail |> extract_items_from_esi_killmail()

              {:error, reason} ->
                Logger.warning("Failed to fetch killmail from ESI: #{inspect(reason)}")
                {:ok, []}
            end

          {:error, :invalid_format} ->
            Logger.warning("Invalid killmail ID format: #{inspect(killmail.killmail_id)}")
            {:ok, []}
        end
    end
  end

  defp extract_dropped_items(%Killmail{esi_data: esi_data} = killmail) do
    Logger.debug("Extracting dropped items",
      esi_data_structure: inspect(esi_data, limit: :infinity),
      category: :item_processing
    )

    items = extract_items_from_esi_data(esi_data, killmail)

    Logger.debug("Extracted items", count: length(items), category: :item_processing)
    {:ok, items}
  end

  defp extract_items_from_esi_data(esi_data, killmail) do
    cond do
      has_victim_items?(esi_data) -> extract_from_victim_items(esi_data)
      has_direct_items?(esi_data) -> extract_from_direct_items(esi_data)
      true -> fetch_items_from_esi_api(esi_data, killmail)
    end
  end

  defp has_victim_items?(%{"victim" => %{"items" => items}}) when is_list(items), do: true
  defp has_victim_items?(_), do: false

  defp has_direct_items?(%{"items" => items}) when is_list(items), do: true
  defp has_direct_items?(_), do: false

  defp extract_from_victim_items(%{"victim" => %{"items" => victim_items}}) do
    Logger.debug("Found victim items", count: length(victim_items), category: :item_processing)
    extract_dropped_from_victim_items(victim_items)
  end

  defp extract_from_direct_items(%{"items" => items}) do
    Logger.debug("Found direct items", count: length(items), category: :item_processing)
    filter_dropped_items(items)
  end

  defp fetch_items_from_esi_api(esi_data, killmail) do
    Logger.debug("No items found in ESI data structure, attempting to fetch from ESI API",
      victim_keys: get_victim_keys(esi_data),
      category: :item_processing
    )

    killmail_id = get_in(esi_data, ["killmail_id"])

    case get_killmail_hash_from_killmail(killmail) do
      nil -> log_and_return_empty_items("No killmail hash available for ESI fetch")
      killmail_hash -> fetch_from_esi_service(killmail_id, killmail_hash)
    end
  end

  defp get_victim_keys(esi_data) do
    if get_in(esi_data, ["victim"]), do: Map.keys(esi_data["victim"]), else: nil
  end

  defp fetch_from_esi_service(killmail_id, killmail_hash) do
    case safe_parse_killmail_id(killmail_id) do
      {:ok, killmail_id_int} ->
        killmail_id_int
        |> ESIService.get_killmail(killmail_hash)
        |> handle_esi_killmail_response()

      {:error, :invalid_format} ->
        Logger.warning("Invalid killmail ID format in ESI fetch: #{inspect(killmail_id)}")
        {:ok, nil}
    end
  end

  defp handle_esi_killmail_response({:ok, esi_killmail}) do
    case extract_items_from_esi_killmail(esi_killmail) do
      {:ok, items} -> items
    end
  end

  defp handle_esi_killmail_response({:error, reason}) do
    log_and_return_empty_items("Failed to fetch killmail from ESI: #{inspect(reason)}")
  end

  defp log_and_return_empty_items(message) do
    Logger.debug(message, category: :item_processing)
    []
  end

  defp extract_dropped_from_victim_items(victim_items) do
    victim_items
    |> Enum.filter(fn item ->
      # Item is dropped if it has quantity_dropped > 0
      Map.get(item, "quantity_dropped", 0) > 0
    end)
    |> Enum.map(fn item ->
      %{
        "type_id" => Map.get(item, "item_type_id"),
        "quantity" => Map.get(item, "quantity_dropped", 0),
        "flag" => Map.get(item, "flag"),
        "singleton" => Map.get(item, "singleton", 0)
      }
    end)
    |> Enum.reject(fn item ->
      is_nil(item["type_id"]) or item["quantity"] <= 0
    end)
  end

  defp filter_dropped_items(items) do
    items
    |> Enum.filter(fn item ->
      # Check if item is marked as dropped or has dropped quantity
      Map.get(item, "dropped", false) or Map.get(item, "quantity_dropped", 0) > 0
    end)
    |> Enum.map(fn item ->
      %{
        "type_id" => Map.get(item, "type_id") || Map.get(item, "item_type_id"),
        "quantity" => Map.get(item, "quantity_dropped") || Map.get(item, "quantity", 1),
        "flag" => Map.get(item, "flag"),
        "singleton" => Map.get(item, "singleton", 0)
      }
    end)
    |> Enum.reject(fn item ->
      is_nil(item["type_id"]) or item["quantity"] <= 0
    end)
  end

  defp identify_and_enrich_notable_items([]) do
    {:ok, []}
  end

  defp identify_and_enrich_notable_items(items) when is_list(items) do
    # First, enrich items with names from ESI
    with {:ok, enriched_items} <- enrich_items_with_names(items),
         {:ok, price_data} <- get_janice_prices_cached(enriched_items) do
      process_priced_items(enriched_items, price_data)
    else
      {:error, reason} -> handle_pricing_error(reason)
    end
  end

  defp enrich_items_with_names(items) do
    # Extract unique type IDs
    type_ids =
      items
      |> Enum.map(fn item ->
        type_id = Map.get(item, "type_id") || Map.get(item, "item_type_id")

        case safe_parse_killmail_id(type_id) do
          {:ok, parsed_type_id} ->
            parsed_type_id

          {:error, :invalid_format} ->
            Logger.warning("Invalid type_id format: #{inspect(type_id)}")
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()

    # Fetch names from ESI with caching
    {:ok, type_names} = get_type_names_cached(type_ids)

    # Add names to items
    enriched_items =
      items
      |> Enum.map(fn item ->
        type_id = to_string(Map.get(item, "type_id") || Map.get(item, "item_type_id"))
        name = Map.get(type_names, type_id, "Unknown Item")
        Map.put(item, "name", name)
      end)

    {:ok, enriched_items}
  end

  defp process_priced_items(items, price_data) do
    notable_items =
      items
      |> enrich_items_with_pricing(price_data)
      |> filter_notable_items()
      |> sort_items_by_value()

    log_notable_items_result(items, notable_items)
    {:ok, notable_items}
  end

  defp enrich_items_with_pricing(items, price_data) do
    Enum.map(items, fn item ->
      type_id = to_string(item["type_id"])
      item_price_data = Map.get(price_data, type_id, %{})
      enrich_item_with_price(item, item_price_data)
    end)
  end

  defp enrich_item_with_price(item, item_price_data) do
    price = Map.get(item_price_data, "price", 0)
    quantity = item["quantity"]

    Map.merge(item, %{
      "name" => Map.get(item_price_data, "name", "Unknown Item"),
      "price" => price,
      "total_value" => price * quantity
    })
  end

  defp filter_notable_items(enriched_items) do
    enriched_items
    |> Enum.filter(&notable_item?/1)
  end

  defp sort_items_by_value(items) do
    Enum.sort_by(items, fn item -> -Map.get(item, "total_value", 0) end)
  end

  defp log_notable_items_result(items, notable_items) do
    Logger.debug("Notable items identified",
      total_items: length(items),
      notable_count: length(notable_items),
      category: :item_processing
    )
  end

  defp handle_pricing_error(reason) do
    Logger.warning("Failed to get item prices from Janice - Error: #{inspect(reason)}")
    {:error, reason}
  end

  defp notable_item?(item) do
    name = Map.get(item, "name", "")
    total_value = Map.get(item, "total_value", 0)
    threshold = Config.get(:notable_item_threshold, 50_000_000)

    # Check if item contains "abyssal" (case insensitive)
    is_abyssal = String.downcase(name) |> String.contains?("abyssal")

    # Check if item value exceeds threshold
    is_valuable = total_value >= threshold

    result = is_abyssal or is_valuable

    if result do
      Logger.debug("Notable item found",
        name: name,
        value: total_value,
        reason:
          cond do
            is_abyssal and is_valuable -> "abyssal_and_valuable"
            is_abyssal -> "abyssal"
            is_valuable -> "valuable"
            true -> "unknown"
          end,
        category: :item_processing
      )
    end

    result
  end

  # Helper functions

  defp get_killmail_hash_from_killmail(%Killmail{zkb: zkb}) when is_map(zkb) do
    Map.get(zkb, "hash")
  end

  defp get_killmail_hash_from_killmail(_), do: nil

  defp extract_items_from_esi_killmail(esi_killmail) do
    Logger.debug("Extracting items from ESI killmail",
      esi_keys: Map.keys(esi_killmail),
      category: :item_processing
    )

    case get_in(esi_killmail, ["victim", "items"]) do
      items when is_list(items) ->
        Logger.debug("Found items in ESI killmail",
          total_items: length(items),
          category: :item_processing
        )

        dropped_items = extract_dropped_from_victim_items(items)
        {:ok, dropped_items}

      _ ->
        Logger.debug("No items found in ESI killmail victim data",
          victim_keys:
            if(get_in(esi_killmail, ["victim"]), do: Map.keys(esi_killmail["victim"]), else: nil),
          category: :item_processing
        )

        {:ok, []}
    end
  end
end
