[
  # False positive from service initialization - application works correctly at runtime
  {"lib/wanderer_notifier/application.ex", :pattern_match, {22, 13}},

  # False positive - utility function handles multiple types but analyzed at specific call sites
  {"lib/wanderer_notifier/domains/notifications/discord/neo_client.ex", :pattern_match, 1},

  # Defensive error handling - the pattern handles future API changes
  {"lib/wanderer_notifier/domains/notifications/determiner.ex", :pattern_match, {260, 16}},
  {"lib/wanderer_notifier/domains/notifications/determiner.ex", :pattern_match, {285, 16}},

  # Pre-existing issues - not related to cleanup
  {"lib/wanderer_notifier/discord_notifier.ex", :pattern_match, {128, 22}},
  {"lib/wanderer_notifier/discord_notifier.ex", :call, {144, 30}},
  {"lib/wanderer_notifier/domains/tracking/handlers/system_handler.ex", :pattern_match, {138, 5}},
  {"lib/wanderer_notifier/domains/tracking/handlers/system_handler.ex", :unused_fun, {150, 8}}
]
