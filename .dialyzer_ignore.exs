[
  # False positive from service initialization - application works correctly at runtime
  {"lib/wanderer_notifier/application.ex", :pattern_match, {22, 13}},

  # False positive - utility function handles multiple types but analyzed at specific call sites
  {"lib/wanderer_notifier/domains/notifications/discord/neo_client.ex", :pattern_match, 1}
]
