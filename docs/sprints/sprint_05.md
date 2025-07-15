# Sprint 5: Phoenix/Ecto Migration Foundation

**Duration**: 2 weeks  
**Priority**: High  
**Goal**: Phoenix framework integration and Ecto schema implementation

## Week 1: Phoenix Setup & Ecto Schemas

### Task 5.1: Phoenix Framework Integration
**Estimated Time**: 2 days  
**Files to Create/Modify**:
- `mix.exs` (add Phoenix dependencies)
- `config/config.exs` (Phoenix configuration)
- `lib/wanderer_notifier_web/endpoint.ex`
- `lib/wanderer_notifier_web/router.ex`

**Implementation Steps**:
1. Add Phoenix dependencies to mix.exs
2. Generate minimal Phoenix structure (no HTML/assets)
3. Configure Phoenix endpoint and router
4. Integrate with existing supervision tree
5. Preserve existing web functionality during migration
6. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
7. **Commit**: "feat: add Phoenix framework integration with minimal setup"

### Task 5.2: Killmail Ecto Schemas
**Estimated Time**: 3 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/killmail/schemas/killmail_data.ex`
- `lib/wanderer_notifier/killmail/schemas/victim.ex`
- `lib/wanderer_notifier/killmail/schemas/attacker.ex`
- `test/wanderer_notifier/killmail/schemas/killmail_data_test.exs`

**Implementation Steps**:
1. Create Ecto embedded schemas for killmail domain
2. Implement comprehensive changeset validations
3. Add custom validation functions for game rules
4. Create schema relationship mappings
5. Add transformation utilities for existing structs
6. Create comprehensive test suite with edge cases
7. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
8. **Commit**: "feat: add Ecto embedded schemas for killmail domain"

### Task 5.3: Map/Character Ecto Schemas
**Estimated Time**: 3 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/map/schemas/character_location.ex`
- `lib/wanderer_notifier/map/schemas/system_activity.ex`
- `lib/wanderer_notifier/map/schemas/wormhole_connection.ex`
- `test/wanderer_notifier/map/schemas/character_location_test.exs`

**Implementation Steps**:
1. Create Ecto schemas for map domain entities
2. Implement validation rules for character tracking
3. Add system activity schema with activity types
4. Create wormhole connection schema with status tracking
5. Add transformation utilities for SSE data
6. Create comprehensive test suite
7. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
8. **Commit**: "feat: add Ecto embedded schemas for map domain"

## Week 2: Phoenix Channels & Integration

### Task 5.4: Phoenix Channels for WebSocket
**Estimated Time**: 3 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier_web/channels/killmail_channel.ex`
- `lib/wanderer_notifier_web/channels/user_socket.ex`
- `lib/wanderer_notifier/killmail/external_websocket_client.ex`
- `test/wanderer_notifier_web/channels/killmail_channel_test.exs`

**Implementation Steps**:
1. Create Phoenix Channel for killmail streaming
2. Implement external WebSocket client as supervised process
3. Add channel message routing and validation
4. Implement connection management and monitoring
5. Add channel authentication and authorization
6. Create comprehensive test suite with mock WebSocket
7. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
8. **Commit**: "feat: replace WebSocket client with Phoenix Channels"

### Task 5.5: Mint.SSE Client Implementation
**Estimated Time**: 3 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/map/mint_sse_client.ex`
- `lib/wanderer_notifier/map/sse_event_processor.ex`
- `test/wanderer_notifier/map/mint_sse_client_test.exs`

**Implementation Steps**:
1. Replace custom SSE client with Mint.SSE
2. Implement robust connection management
3. Add automatic reconnection with exponential backoff
4. Create event processing pipeline with schemas
5. Add comprehensive error handling and logging
6. Create test suite with mock SSE streams
7. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
8. **Commit**: "feat: replace custom SSE client with Mint.SSE implementation"

### Task 5.6: Schema Integration with Existing Pipeline
**Estimated Time**: 2 days  
**Files to Modify**:
- `lib/wanderer_notifier/killmail/pipeline.ex`
- `lib/wanderer_notifier/map/pipeline.ex`
- Update notification and processing modules

**Implementation Steps**:
1. Update killmail pipeline to use Ecto schemas
2. Update map pipeline to use new schemas
3. Add schema validation in processing pipeline
4. Update notification formatters for schema data
5. Ensure backward compatibility during transition
6. Run full test suite and performance benchmarks
7. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
8. **Commit**: "refactor: integrate Ecto schemas with existing processing pipeline"