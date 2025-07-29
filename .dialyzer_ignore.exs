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
  
  # Pattern coverage warnings from simplified pipeline - false positives as strings can be passed
  {"lib/wanderer_notifier/domains/killmail/simplified_pipeline.ex", :pattern_match_cov, 182},
  {"lib/wanderer_notifier/domains/killmail/simplified_pipeline.ex", :pattern_match_cov, 201},
  
  # False positive from service initialization - application works correctly at runtime
  {"lib/wanderer_notifier/application.ex", :pattern_match, {21, 13}}
]