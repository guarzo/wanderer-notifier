[
  # These are false positives from macro-generated code in BaseMapClient
  {"lib/wanderer_notifier/map/clients/characters_client.ex", :unused_fun, 6},
  {"lib/wanderer_notifier/map/clients/systems_client.ex", :unused_fun, 6},
  {"lib/wanderer_notifier/map/clients/characters_client.ex", :pattern_match_cov, 6},
  {"lib/wanderer_notifier/map/clients/systems_client.ex", :pattern_match_cov, 6},
  # False positive from macro-generated code in Config module
  {"lib/wanderer_notifier/shared/config/config.ex", :pattern_match, 1},
  
  # Current Dialyzer false positives after Sprint 3 cleanup
  {"lib/wanderer_notifier/api/controllers/system_info.ex", :pattern_match, 372},
  {"lib/wanderer_notifier/domains/killmail/killmail.ex", :pattern_match_cov, 179},
  {"lib/wanderer_notifier/domains/killmail/websocket_client.ex", :pattern_match, 773},
  {"lib/wanderer_notifier/domains/killmail/websocket_client.ex", :pattern_match, 808},
  {"lib/wanderer_notifier/domains/killmail/websocket_client.ex", :unused_fun, 821},
  {"lib/wanderer_notifier/domains/killmail/websocket_client.ex", :unused_fun, 828},
  {"lib/wanderer_notifier/domains/notifications/utils.ex", :invalid_contract, 90},
  {"lib/wanderer_notifier/domains/notifications/utils.ex", :invalid_contract, 97},
  {"lib/wanderer_notifier/domains/notifications/utils.ex", :invalid_contract, 104},
  
  
  # False positive from service initialization - application works correctly at runtime
  {"lib/wanderer_notifier/application.ex", :pattern_match, {22, 13}},
  
  # False positives - dialyzer incorrectly infers these fields can't be nil in these specific flows
  {"lib/wanderer_notifier/domains/killmail/pipeline.ex", :guard_fail, 205},
  {"lib/wanderer_notifier/domains/killmail/pipeline.ex", :guard_fail, 206},
  {"lib/wanderer_notifier/domains/killmail/pipeline.ex", :guard_fail, 374},
  {"lib/wanderer_notifier/domains/killmail/pipeline.ex", :guard_fail, 375},
  
  # False positives - utility functions that handle multiple types but analyzed at specific call sites
  {"lib/wanderer_notifier/domains/notifications/discord/neo_client.ex", :pattern_match_cov, 91},
  {"lib/wanderer_notifier/domains/notifications/discord/neo_client.ex", :pattern_match, 826},
  {"lib/wanderer_notifier/domains/notifications/discord/neo_client.ex", :pattern_match_cov, 829},
  {"lib/wanderer_notifier/domains/tracking/static_info.ex", :pattern_match, 392},
  {"lib/wanderer_notifier/domains/tracking/static_info.ex", :guard_fail, 393},
  {"lib/wanderer_notifier/domains/tracking/static_info.ex", :pattern_match_cov, 402}
]