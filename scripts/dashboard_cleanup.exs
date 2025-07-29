#!/usr/bin/env elixir

# Script to show which functions to keep in the dashboard controller

# Functions we NEED to keep:
keep_functions = [
  "render/1",  # Main render function
  "render_dashboard/1",
  "render_head/0",
  "render_header/2",  # Updated header with status
  "format_uptime/1",
  "render_tracking_card/1",
  "render_notifications_card/1", 
  "render_performance_card/1",
  "render_cache_stats_card/1",
  "render_footer/1",
  "get_refresh_interval/0",
  "get_stats_value_class/2",
  "get_notification_type_icon/1",
  "get_performance_status_color/1",
  "get_hit_rate_class/1",
  "get_eviction_rate_class/1",
  "match _"  # Error handler
]

IO.puts("Functions to KEEP in dashboard_controller.ex:")
Enum.each(keep_functions, &IO.puts("  - #{&1}"))

IO.puts("\nAll other functions should be removed!")