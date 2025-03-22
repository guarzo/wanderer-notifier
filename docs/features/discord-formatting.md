# Discord Formatting

This document outlines the formatting standards and best practices for Discord messages in the WandererNotifier application.

## Overview

WandererNotifier delivers various notification types to Discord channels. Consistent formatting ensures that these notifications are readable, visually distinctive, and contain all the necessary information for users. The application uses Discord's rich embed format for most notifications, with a consistent color scheme and layout structure.

## Embed Structure

### Common Elements

All notification embeds share these common elements:

- **Title**: Descriptive title with notification type (e.g., "System Alert", "Character Alert")
- **Color**: Consistent color coding based on notification type
- **Thumbnail**: Relevant image (ship type, character portrait, etc.)
- **Footer**: Attribution and timestamp
- **Fields**: Structured data fields with clear labels

### Color Coding

Notifications use a consistent color scheme for quick visual identification:

| Notification Type | Color (Hex) | Description                            |
| ----------------- | ----------- | -------------------------------------- |
| Kill Alert        | `#E74C3C`   | Red for destruction notifications      |
| System Alert      | `#3498DB`   | Blue for system tracking notifications |
| Character Alert   | `#2ECC71`   | Green for character notifications      |
| Chart             | `#9B59B6`   | Purple for chart and data visuals      |
| Error             | `#E67E22`   | Orange for error messages              |

### Layout Consistency

Each notification type follows a consistent layout pattern:

1. **Header section**: Title and brief description
2. **Main content**: Primary information fields
3. **Context section**: Additional information and metadata
4. **Footer**: Source attribution and timestamp

## Notification Types

### Kill Notifications

```
[KILL ALERT]
Victim: John Doe (ALLIANCE)
Ship: Vindicator
System: J123456 (C5)
Value: 1,250,000,000 ISK
Final Blow: Jane Smith (ENEMIES)
```

Key elements:

- Red color coding (#E74C3C)
- Ship type thumbnail
- Value formatted with commas
- System with wormhole class when applicable
- Link to zkillboard for the specific kill

### System Notifications

```
[SYSTEM ALERT]
System: J123456 (C5)
Region: Unknown Space
Static Connections: C5, Null
Recent Activity: 3 kills in last hour
Status: New system added to tracking
```

Key elements:

- Blue color coding (#3498DB)
- System name with wormhole class
- Static connection information when available
- Recent activity summary
- Map link to the system

### Character Notifications

```
[CHARACTER ALERT]
Character: John Doe
Corporation: Example Corp [CORP]
Alliance: Example Alliance [ALLI]
Last Seen: J123456 (5 minutes ago)
Ships: Astero, Stratios
Status: New character in tracked system
```

Key elements:

- Green color coding (#2ECC71)
- Character portrait
- Corporation and alliance tags in brackets
- Last seen location with recency
- Common ship types when available

### Chart Notifications

```
[TPS CHART]
Title: Tranquility Server Performance
Period: Last 24 Hours
Peak: 25,432 TPS
Average: 18,756 TPS
Generated: 2023-06-01 12:00 UTC
```

Key elements:

- Purple color coding (#9B59B6)
- Chart image as attachment
- Key statistics in text fields
- Generation timestamp
- Time period covered

## Formatting Rules

### Text Formatting

- **Bold** is used for important values: `**25,432** TPS`
- _Italics_ for supplementary information: `*Last updated 5 minutes ago*`
- `Code blocks` for technical identifiers: `System ID: \`12345\``
- > Quotes for direct data or messages

### Number Formatting

- Large numbers use comma separators: `1,250,000,000 ISK`
- Percentages include one decimal place: `25.5%`
- Times use 24-hour format with timezone: `12:00 UTC`

### Link Formatting

- Text links use descriptive labels: `[View on zKillboard](https://zkillboard.com/kill/12345/)`
- Multiple links are separated with pipes: `[Map](link) | [zKill](link) | [ESI](link)`

## Implementation

The Discord formatting is implemented in the `WandererNotifier.Discord.Formatter` module, which includes specialized formatters for each notification type:

- `KillFormatter` - For kill notifications
- `SystemFormatter` - For system tracking alerts
- `CharacterFormatter` - For character tracking alerts
- `ChartFormatter` - For chart notifications

Each formatter implements the `format/1` function that takes the notification data and returns a formatted Discord embed map.

## Example Embed Structure

```elixir
%{
  title: "Kill Alert: John Doe",
  description: "Ship destroyed in J123456",
  color: 0xE74C3C,
  thumbnail: %{
    url: "https://images.evetech.net/types/12345/render"
  },
  fields: [
    %{name: "Ship", value: "Vindicator", inline: true},
    %{name: "Value", value: "1,250,000,000 ISK", inline: true},
    %{name: "System", value: "J123456 (C5)", inline: true},
    %{name: "Final Blow", value: "Jane Smith", inline: true}
  ],
  footer: %{
    text: "Data via zKillboard • 2023-06-01 12:00 UTC"
  }
}
```

## Notification Delivery

Formatted embeds are sent to Discord via webhooks using the `WandererNotifier.Discord.Service` module. The service:

1. Takes the formatted embed and attaches any relevant files (e.g., charts)
2. Determines the appropriate channel based on notification type and configuration
3. Sends the message to the Discord webhook
4. Handles rate limiting and retries if necessary

## Testing

For testing Discord formatting:

1. Use the `/api/test-notification` endpoint, which will generate a test notification
2. Check the logs with the tag `FORMATTER TRACE` to see the formatted embed
3. Verify the notification appears correctly in the Discord channel

## Best Practices

1. **Consistency**: Maintain consistent formatting across all notification types
2. **Readability**: Ensure text is readable with proper spacing and formatting
3. **Conciseness**: Keep notifications brief while including all essential information
4. **Color Coding**: Use the standard color scheme for quick visual identification
5. **Links**: Always include relevant links for additional information
6. **Images**: Use thumbnails and attachments sparingly to avoid clutter
7. **Testing**: Test all notification types in both light and dark Discord themes
