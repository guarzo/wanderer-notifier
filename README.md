# Killmail Pipeline Refactoring

## Project Overview

The Wanderer Notifier processes killmail data from EVE Online to track and notify users about important kills. This repository includes the ongoing refactoring of the killmail processing pipeline to improve maintainability, testability, and performance.

## Refactoring Progress

### ✅ Completed:

1. **Architecture Redesign**

   - Created a unified `KillmailProcessor` module as the central coordinator
   - Implemented proper error handling with the `with` pattern
   - Established clear stages in the processing pipeline

2. **Data Structure Improvements**

   - Redesigned `KillmailData` struct with flattened field structure
   - Eliminated nested data for easier access
   - Standardized field naming and nullability

3. **Core Components**

   - Created a focused `NotificationDeterminer` module
   - Implemented a simplified `Persistence` module
   - Added a clean `Enrichment` module
   - Created backward-compatible `Pipeline` module

4. **Transitional Tools**
   - Added `DataAccess` module as a simpler alternative to `Extractor`
   - Created migration guide for updating code
   - Implemented test coverage for new components

### 🔄 In Progress:

1. **Extractor and Transformer Simplification**

   - Transitioning from Extractor module to direct KillmailData access
   - Simplifying Transformer methods to focus on essential conversions

2. **Comprehensive Testing**
   - Building test fixtures and helpers
   - Implementing both unit and integration tests

### 📋 Next Steps:

1. **Follow the Migration Guide**

   - Use the guide in `docs/migration-guide-extractor-to-direct-access.md`
   - Start with high-impact modules first
   - Run tests between each module migration

2. **Update Remaining Code**

   - Search for direct uses of Extractor and replace with direct access
   - Remove unused or redundant Transformer methods
   - Ensure consistent error handling

3. **Performance Optimization**
   - Implement proper batching for database operations
   - Add caching where appropriate
   - Profile and optimize bottlenecks

## Development

### Running Tests

```bash
mix test
```

### Style Guide

This project follows Elixir's standard style guide with the following additions:

- Use the `with` pattern for multi-stage operations
- Prefer direct struct access over helper functions for simple fields
- Use DataAccess module for complex data extraction

## License

This project is licensed according to the terms in the LICENSE file.

## Support

If you encounter issues or have questions, please open an issue on the project repository.

## Notes

```
 mix archive.install hex bunt

 docker buildx build . \
  --build-arg WANDERER_NOTIFIER_API_TOKEN=your_token_here \
  --build-arg APP_VERSION=local \
  -t notifier:local

  docker run \
    --publish=7474:7474 --publish=7687:7687 \
    --volume=$HOME/neo4j/data:/data \
    --volume=$HOME/neo4j/logs:/logs \
    neo4j:latest

      WandererNotifier.Debug.KillmailTools.log_next_killmail()
```
