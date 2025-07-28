# System Notification Validation & Regression Prevention

## Overview

This document describes the validation approach for system notifications to prevent the regression where notifications were dramatically simplified and lost critical content.

## The Problem That Was Fixed

Previously, system notifications only showed:
- System name
- System ID

**All other critical information was missing:**
- ❌ No wormhole class (C1, C2, C3, C4, C5, C6)
- ❌ No static wormhole connections  
- ❌ No recent kills data
- ❌ No region information with links
- ❌ No wormhole effects (Pulsar, Magnetar, etc.)
- ❌ No proper color coding
- ❌ No clickable links to Dotlan
- ❌ No rich descriptions

## What Was Restored ✅

System notifications now include **ALL** the following fields:

### Core Fields (All Systems)
1. **System**: `[J155416](https://evemaps.dotlan.net/system/J155416)` - Clickable Dotlan link
2. **Region**: `[D-R00018](https://evemaps.dotlan.net/region/D-R00018)` - Clickable Dotlan link

### Wormhole-Specific Fields  
3. **Class**: `C4` - Shows wormhole class
4. **Static Wormholes**: `C247, P060` - Lists static connections
5. **Effect**: `Pulsar` - Shows wormhole effect if present
6. **Shattered**: `Yes` - Shows if system is shattered (when applicable)

### Dynamic Fields
7. **Recent Kills**: Shows formatted recent kills with ISK values, points, and zKillboard links:
   ```
   [138.7M ISK kill](https://zkillboard.com/kill/128846484/) (14 pts)
   [10.0K ISK kill](https://zkillboard.com/kill/128845720/) (1 pts)
   [20.1K ISK kill](https://zkillboard.com/kill/128845711/) (1 pts)
   ```

### Visual Enhancements
- **Color Coding**: Purple for wormholes, green for high-sec, yellow for low-sec, red for null-sec
- **Thumbnails**: Proper system type icons
- **Rich Descriptions**: "A new wormhole system (C4) has been added to tracking."
- **Footer**: "System ID: 31001503"

## Manual Validation Process

Since the test environment has complex mock setup issues, here's how to manually validate the system notifications work correctly:

### 1. Start the Application
```bash
make s  # Clean compile and start
```

### 2. Test Wormhole System Notification
In the IEx shell, run:
```elixir
# Create a comprehensive wormhole system
system_data = %{
  "solar_system_id" => "31001503",
  "name" => "J155416",
  "region_name" => "D-R00018", 
  "system_type" => "wormhole",
  "class_title" => "C4",
  "statics" => ["C247", "P060"], 
  "effect_name" => "Pulsar",
  "is_shattered" => false,
  "security_status" => -1.0
}

system_struct = WandererNotifier.Domains.Tracking.Entities.System.from_api_data(system_data)
formatted = WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter.format_notification(system_struct)

# Check results
IO.puts("Title: #{formatted.title}")
IO.puts("Description: #{formatted.description}")  
IO.puts("Field count: #{length(formatted.fields)}")
IO.puts("Fields:")
Enum.each(formatted.fields, fn field ->
  IO.puts("  #{field.name}: #{field.value}")
end)
```

### 3. Expected Results ✅

**Minimum Requirements (Regression Prevention):**
- ✅ Field count: **≥ 5** (System, Class, Static Wormholes, Region, Effect)
- ✅ Title: `"New System Tracked: J155416"`
- ✅ Description: Contains "wormhole system" and "C4"
- ✅ Color: `4361162` (wormhole purple)
- ✅ All links properly formatted with `[text](url)` syntax

### 4. Test K-Space System (Verification)
```elixir
kspace_data = %{
  "solar_system_id" => "30000142",
  "name" => "Jita",
  "region_name" => "The Forge",
  "system_type" => "highsec",
  "security_status" => 0.946
}

kspace_system = WandererNotifier.Domains.Tracking.Entities.System.from_api_data(kspace_data)
kspace_formatted = WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter.format_notification(kspace_system)

# Should NOT have wormhole-specific fields
field_names = Enum.map(kspace_formatted.fields, & &1.name)
IO.puts("K-space fields: #{inspect(field_names)}")
# Should see: ["System", "Region"] but NOT ["Class", "Static Wormholes", "Effect"]
```

### 5. Test Recent Kills Integration
```elixir
# Test recent kills function directly  
result = WandererNotifier.Domains.Killmail.Enrichment.recent_kills_for_system(30000142, 3)
IO.puts("Recent kills result:")
IO.puts(result)
# Should show formatted kills with ISK values and zKillboard links
```

## Key Files to Monitor for Regressions

### 1. Core Formatter
- **File**: `lib/wanderer_notifier/domains/notifications/formatters/notification_formatter.ex`
- **Key Function**: `format_system_notification/1` (lines 268-299)
- **Critical**: Must call `build_system_fields/2` and include all field types

### 2. Field Building Logic  
- **File**: Same as above
- **Key Functions**: Lines 320-440
  - `add_system_field/2` - System links
  - `add_class_field/3` - Wormhole class
  - `add_statics_field/3` - Static wormholes
  - `add_region_field/2` - Region links  
  - `add_effect_field/3` - Wormhole effects
  - `add_recent_kills_field/2` - Recent kills

### 3. System Type Detection
- **File**: `lib/wanderer_notifier/domains/tracking/static_info.ex`
- **Key Function**: `determine_system_type/2` (lines 283-300)
- **Critical**: Must set `system_type: "wormhole"` for wormhole systems

### 4. Recent Kills HTTP Client
- **File**: `lib/wanderer_notifier/domains/killmail/enrichment.ex`
- **Key Function**: `get_system_kills/2` (lines 87-143)
- **Critical**: Must handle JSON response parsing correctly

## Regression Detection Checklist

When making changes to notification-related code, verify:

1. **Field Count**: Wormhole notifications have ≥ 5 fields
2. **Field Names**: All required fields present (System, Class, Static Wormholes, Region, Effect)
3. **Link Format**: All links use `[text](url)` format and point to correct URLs
4. **Color Coding**: Proper colors for each system type
5. **Rich Descriptions**: Descriptions mention system type and wormhole class
6. **Recent Kills**: HTTP requests work and format kills correctly
7. **Error Handling**: Empty/null data doesn't crash the formatter

## Quick Smoke Test

Run this one-liner to verify core functionality:
```bash
echo 'system = WandererNotifier.Domains.Tracking.Entities.System.from_api_data(%{"solar_system_id" => "31001503", "name" => "J155416", "system_type" => "wormhole", "class_title" => "C4", "statics" => ["C247"], "region_name" => "Test"}); formatted = WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter.format_notification(system); IO.puts("Field count: #{length(formatted.fields)} (expected: ≥5)"); IO.puts("Fields: #{inspect(Enum.map(formatted.fields, & &1.name))}"); System.halt()' | iex -S mix
```

Expected output:
```
Field count: 5 (expected: ≥5)  
Fields: ["System", "Class", "Static Wormholes", "Region", "Recent Kills"]
```

## Automated Testing (Future)

Once the test environment mock issues are resolved, run:
```bash
mix test test/wanderer_notifier/integration/system_notification_integration_test.exs
```

This comprehensive test suite validates all aspects of system notifications and prevents regressions.