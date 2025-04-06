# Logging Migration Analysis Report

Generated on: 2025-04-05 18:16:59.968910Z

## Overview

Total files analyzed: 166
Files needing migration: 76

## Direct Logger Usage

Files with direct Logger calls: 11

### Files with Direct Logger Calls

| File | Direct Logger Calls |
| ---- | ------------------ |
| wanderer_notifier/chart_service/chart_service_manager.ex | 74 |
| wanderer_notifier/release.ex | 38 |
| wanderer_notifier/api/map/response_validator.ex | 30 |
| wanderer_notifier/logger/logger.ex | 22 |
| wanderer_notifier/notifiers/helpers/test_notifications.ex | 22 |
| wanderer_notifier/data/cache/cachex_impl.ex | 12 |
| wanderer_notifier/api/zkill/client.ex | 8 |
| wanderer_notifier/api/http/client.ex | 4 |
| wanderer_notifier/killmail_processing/metrics.ex | 4 |
| wanderer_notifier/resources/killmail_aggregation.ex | 4 |
| wanderer_notifier/notifiers/discord/notifier.ex | 2 |

## Missing Proper Alias

| File |
| ---- |


## Migration Opportunities

### Boolean Flag Candidates

| File | Count |
| ---- | ----- |
| wanderer_notifier/core/application/service.ex | 66 |
| wanderer_notifier/logger/logger.ex | 51 |
| wanderer_notifier/license/service.ex | 48 |
| wanderer_notifier/chart_service/chart_service_manager.ex | 45 |
| wanderer_notifier/resources/tracked_character.ex | 45 |
| wanderer_notifier/api/controllers/chart_controller.ex | 42 |
| wanderer_notifier/api/map/characters_client.ex | 42 |
| wanderer_notifier/api/zkill/websocket.ex | 39 |
| wanderer_notifier/processing/killmail/comparison.ex | 39 |
| wanderer_notifier/license/client.ex | 36 |
| wanderer_notifier/chart_service/activity_chart_adapter.ex | 30 |
| wanderer_notifier/notifiers/structured_formatter.ex | 24 |
| wanderer_notifier/api/map/characters.ex | 21 |
| wanderer_notifier/resources/killmail_persistence.ex | 21 |
| wanderer_notifier/schedulers/base_scheduler.ex | 21 |
| wanderer_notifier/api/map/activity_chart_scheduler.ex | 18 |
| wanderer_notifier/chart_service/killmail_chart_adapter.ex | 18 |
| wanderer_notifier/api/character/kills_service.ex | 15 |
| wanderer_notifier/api/map/client.ex | 15 |
| wanderer_notifier/core/stats.ex | 15 |

### Batch Logging Candidates

| File | Count |
| ---- | ----- |
| wanderer_notifier/processing/killmail/processor.ex | 12 |
| wanderer_notifier/api/map/characters.ex | 9 |
| wanderer_notifier/api/zkill/websocket.ex | 9 |
| wanderer_notifier/api/controllers/character_controller.ex | 6 |
| wanderer_notifier/core/application/service.ex | 6 |
| wanderer_notifier/notifiers/discord/notifier.ex | 6 |
| wanderer_notifier/processing/killmail/comparison.ex | 6 |
| wanderer_notifier/api/http/error_handler.ex | 3 |
| wanderer_notifier/license/client.ex | 3 |
| wanderer_notifier/logger/batch_logger.ex | 3 |
| wanderer_notifier/logger/logger.ex | 3 |
| wanderer_notifier/notifiers/discord/neo_client.ex | 3 |
| wanderer_notifier/resources/killmail_persistence.ex | 3 |
| wanderer_notifier/resources/tracked_character.ex | 3 |

### Key-Value Logging Candidates

| File | Count |
| ---- | ----- |
| wanderer_notifier/api/map/characters_client.ex | 32 |
| wanderer_notifier/api/controllers/chart_controller.ex | 26 |
| wanderer_notifier/chart_service/chart_service_manager.ex | 26 |
| wanderer_notifier/resources/tracked_character.ex | 22 |
| wanderer_notifier/license/service.ex | 20 |
| wanderer_notifier/notifiers/discord/notifier.ex | 18 |
| wanderer_notifier/processing/killmail/enrichment.ex | 18 |
| wanderer_notifier/release.ex | 18 |
| wanderer_notifier/api/map/systems_client.ex | 16 |
| wanderer_notifier/chart_service/killmail_chart_adapter.ex | 16 |
| wanderer_notifier/core/application/service.ex | 16 |
| wanderer_notifier/api/zkill/client.ex | 14 |
| wanderer_notifier/logger/startup_tracker.ex | 14 |
| wanderer_notifier/notifiers/structured_formatter.ex | 14 |
| wanderer_notifier/api/map/characters.ex | 12 |
| wanderer_notifier/chart_service/node_chart_adapter.ex | 12 |
| wanderer_notifier/data/cache/cachex_impl.ex | 12 |
| wanderer_notifier/api/http/client.ex | 10 |
| wanderer_notifier/notifiers/helpers/test_notifications.ex | 10 |
| wanderer_notifier/resources/killmail_persistence.ex | 10 |