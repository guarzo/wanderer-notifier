[
  # False positive from service initialization - application works correctly at runtime
  {"lib/wanderer_notifier/application.ex", :pattern_match, {22, 13}},

  # False positive - utility function handles multiple types but analyzed at specific call sites
  {"lib/wanderer_notifier/domains/notifications/discord/neo_client.ex", :pattern_match, 1},

  # Defensive nil guard - map_name() spec says binary but runtime may differ
  {"lib/wanderer_notifier/api/controllers/system_info.ex", :pattern_match, {245, 8}}
]
