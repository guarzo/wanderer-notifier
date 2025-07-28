# Notable Items Feature Implementation Plan

## Overview
Add support for displaying notable items (destroyed/dropped) in kill notifications. Notable items are defined as:
- Any item containing "abyssal" in the name
- Any item worth more than 50M ISK

## Implementation Steps

### 1. Extend Killmail Data Structure
**File**: `lib/wanderer_notifier/domains/killmail/killmail.ex`

Add fields to the Killmail struct:
```elixir
defstruct [
  # ... existing fields ...
  :items_destroyed,     # List of destroyed items
  :items_dropped,       # List of dropped items
  :notable_items,       # Processed list of notable items with values
  # ... rest ...
]
```

### 2. Create Janice API Client
**New File**: `lib/wanderer_notifier/infrastructure/adapters/janice_client.ex`

Create a new module to interact with Janice API for price appraisals:
- Endpoint: `https://janice.e-351.com/api/rest/v2/appraisal`
- Parameters:
  - market=2
  - designation=appraisal
  - pricing=buy
  - pricingVariant=immediate
  - persist=true
  - compactize=true
  - pricePercentage=1
- Authentication: Bearer token from environment variable

Key functions:
- `appraise_items/1` - Bulk appraise multiple items
- `format_appraisal_request/1` - Format items for Janice API
- Handle rate limiting and errors

### 3. Add Configuration
**File**: `config/runtime.exs`

Add Janice API configuration with graceful handling when token is not present:
```elixir
config :wanderer_notifier,
  janice_api_token: System.get_env("JANICE_API_TOKEN"),
  janice_api_url: System.get_env("JANICE_API_URL", "https://janice.e-351.com"),
  notable_item_threshold: System.get_env("NOTABLE_ITEM_THRESHOLD", "50000000") |> String.to_integer(),
  notable_items_enabled: System.get_env("JANICE_API_TOKEN") != nil
```

Note: The `notable_items_enabled` flag is automatically set based on whether the Janice API token is present.

### 4. Update HTTP Client Configuration
**File**: `lib/wanderer_notifier/infrastructure/http/http.ex`

Add Janice service configuration:
```elixir
@service_configs %{
  # ... existing configs ...
  janice: %{
    timeout: 15_000,
    retry_count: 2,
    rate_limit: 5  # Adjust based on API limits
  }
}
```

### 5. Implement Item Processing
**New File**: `lib/wanderer_notifier/domains/killmail/item_processor.ex`

Create module to process killmail items with built-in token checking:
- Check if Janice API is configured before processing
- Extract items from ESI killmail data
- Filter for notable items (abyssal or high value)
- Batch price lookups via Janice API
- Cache prices to reduce API calls

Key functions:
- `enabled?/0` - Check if Janice API token is configured
- `process_killmail_items/1` - Main entry point (returns unchanged killmail if disabled)
- `extract_items/1` - Extract destroyed/dropped items
- `filter_notable_items/2` - Apply filtering rules
- `enrich_with_prices/1` - Add ISK values via Janice

Example implementation:
```elixir
def enabled? do
  Config.get(:janice_api_token) != nil
end

def process_killmail_items(%Killmail{} = killmail) do
  if enabled?() do
    do_process_items(killmail)
  else
    {:ok, killmail}
  end
end
```

### 6. Update Killmail Pipeline
**File**: `lib/wanderer_notifier/domains/killmail/pipeline.ex`

Integrate item processing into the pipeline with automatic disabling when no API token:
```elixir
defp process_with_kill_id(killmail_data, kill_id) do
  # ... existing code ...
  
  # Add item processing step only if enabled
  |> maybe_process_items()
  
  # ... rest of pipeline ...
end

defp maybe_process_items(%Killmail{} = killmail) do
  if Config.get(:notable_items_enabled, false) do
    process_items(killmail)
  else
    # Skip item processing if Janice API token not configured
    killmail
  end
end

defp process_items(%Killmail{} = killmail) do
  case ItemProcessor.process_killmail_items(killmail) do
    {:ok, enriched_killmail} -> enriched_killmail
    {:error, reason} ->
      Logger.warn("Failed to process items", reason: reason)
      killmail
  end
end
```

### 7. Update Notification Formatter
**File**: `lib/wanderer_notifier/domains/notifications/formatters/notification_formatter.ex`

Based on the loot.png example, update the notification format to include notable loot inline:

```elixir
defp build_kill_fields(%Killmail{} = killmail) do
  # Build the main description field with all the kill details
  main_description = build_main_kill_description(killmail)
  
  # Add notable loot section if present
  notable_loot_str = build_notable_loot_section(killmail)
  
  # Add value and timestamp inline
  value_str = if killmail.value && killmail.value > 0 do
    "\n\n**Value:** #{Utils.format_isk(killmail.value)} • #{format_timestamp(killmail)}"
  else
    "\n\n#{format_timestamp(killmail)}"
  end
  
  full_description = main_description <> notable_loot_str <> value_str
  
  [
    Utils.build_field("\u200B", full_description, false)
  ]
end

defp build_notable_loot_section(%Killmail{notable_items: nil}), do: ""
defp build_notable_loot_section(%Killmail{notable_items: []}), do: ""
defp build_notable_loot_section(%Killmail{notable_items: items}) when is_list(items) do
  # Format as shown in loot.png
  items_text = items
    |> Enum.map(&format_notable_item/1)
    |> Enum.join("\n")
  
  "\n\n**Notable Loot**\n#{items_text}"
end

defp format_notable_item(item) do
  # Format: "Abyssal Stasis Webifier x1"
  # or: "50MN Abyssal Microwarpdrive x1"
  quantity_str = if item.quantity > 1, do: " x#{item.quantity}", else: ""
  "#{item.name}#{quantity_str}"
end
```

Note: The display format should match loot.png exactly:
- Section header: "Notable Loot" (not "Notable Items")
- Simple item listing without prices or icons
- Items shown as "Item Name x1" format
- Positioned between the kill description and the value/timestamp line

### 8. Add Caching for Item Prices
**File**: `lib/wanderer_notifier/infrastructure/cache/keys_simple.ex`

Add cache key generation for item prices:
```elixir
def item_price(type_id), do: "janice:item:#{type_id}"
```

Cache prices with appropriate TTL (e.g., 6 hours) to reduce API calls.

### 9. Error Handling & Fallbacks
- Gracefully handle Janice API failures
- Continue processing killmails even if price lookup fails
- Log warnings but don't block notifications
- Consider adding a feature flag to disable notable items

### 10. Testing
Create comprehensive tests:
- `test/wanderer_notifier/infrastructure/adapters/janice_client_test.exs`
- `test/wanderer_notifier/domains/killmail/item_processor_test.exs`
- Update existing killmail formatter tests
- Add fixtures for killmails with items

## Data Flow
1. Killmail received via WebSocket/API with ESI data including items
2. Pipeline extracts destroyed/dropped items from ESI data
3. ItemProcessor filters for abyssal items and prepares batch for pricing
4. JaniceClient performs bulk price appraisal
5. Notable items (abyssal or >50M ISK) are attached to killmail
6. Formatter includes notable items in Discord notification

## Environment Variables
Add to `.env` and documentation:
```
JANICE_API_TOKEN=your_token_here
JANICE_API_URL=https://janice.e-351.com  # Optional, has default
NOTABLE_ITEM_THRESHOLD=50000000  # Optional, defaults to 50M
```

## Performance Considerations
- Batch Janice API calls to reduce request count
- Implement caching for item prices (6-hour TTL)
- Process items asynchronously if possible
- Add circuit breaker for Janice API failures

## Security Considerations
- Store Janice API token securely
- Never log the API token
- Validate item data before sending to Janice
- Rate limit Janice API calls

## Rollout Strategy
1. Feature is automatically enabled/disabled based on `JANICE_API_TOKEN` presence
2. Deploy without token first to ensure no breaking changes
3. Add token to enable the feature for testing
4. Monitor Janice API usage and adjust rate limits
5. Feature gracefully degrades - killmails display normally without notable items if API is unavailable

## Future Enhancements
- Configurable notable item rules (by item group, meta level, etc.)
- Different thresholds for different item types
- Aggregate statistics (total dropped value, etc.)
- Icons for different item categories