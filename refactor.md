# Detailed Implementation Plan

Below is a step‐by‐step plan to refactor and reorganize the codebase. All inline code references are escaped so you can copy the entire block as a single Markdown file.

---

## 1. Consolidate Behaviours

- [x] **Choose a single Behaviour interface**
  - Decided on one module (`Notification`) that defines:
    - `determine/1`
    - `format/1`
    - `deliver/1`
- [x] **Rename and merge files**
  - Renamed `lib/wanderer_notifier/notifications/behaviour.ex` → `lib/wanderer_notifier/notifications/notification.ex`
  - Deleted `factory_behaviour.ex` and `interface.ex`
- [x] **Update implementations**
  - In each determiner, formatter, and notifier adapter:
    - Updated to use `@behaviour Notifications.Notification`
    - Removed other `@behaviour …` lines
- [x] **Refactor Factory/Dispatcher**
  - Renamed `notifications/factory.ex` → `notifications/dispatcher.ex`
  - Changed calls from `Notifications.Factory.dispatch/1` → `Notifications.Dispatcher.run/1`
  - Inlined simple logic where appropriate

---

## 2. Refactor Notifiers Helpers

- [x] **Merge Test Notifiers**
  - Combined `notifiers/test.ex` and `notifiers/test_notifier.ex` into `lib/wanderer_notifier/notifiers/test_notifier.ex`
  - Now implements `@behaviour Notifications.Notification` and all required callbacks
- [x] **Remove duplicate formatters**
  - Removed old contents of `notifications/formatters/…` and moved the contents of `lib/wanderer_notifier/notifiers/formatters` to that location
  - Updated all imports and usage accordingly
  - Restored and fixed `character_utils.ex` and all formatter modules/namespaces

## 3. Configuration & Versioning

- [ ] **Consolidate version logic**
  - Move all version functions into `lib/wanderer_notifier/config/version.ex`
  - In `config/config.ex`, call `Config.Version.version/0`
- [ ] **Standardize ENV loading**
  - Replace custom `fetch!/1` + `parse_int/2` with Dotenvy
  - Example:
    ```elixir
    config :my_app, MyApp.Repo,
      port: {:system, "DB_PORT", 5432}
    ```

---

## 6. API Layer Consistency

- [ ] **Pick Plug and remove phoenix**
  - Extract shared plugs into a single `ApiPipeline` module and import in each file
- [ ] **Extract common parsing/response**
  - New `lib/wanderer_notifier/api/helpers.ex` with functions like `render_json/2`, `parse_body/1`
  - Update controllers to one-liner actions

---

## 7. CI / Scripts DRYness

- [ ] **GitHub Actions**
  - Create a single `.github/workflows/build_and_test.yml` with YAML anchors for shared steps
  - Use `!include` or composite actions if needed

---

### Verification & Rollout

- [ ] **Write or update tests** to cover behavior changes (especially for deduplication and scheduler)
- [ ] **Code review & merge** one area at a time, verifying end-to-end functionality
- [ ] **Release** with a clear changelog highlighting removed files and new module locations

This plan will systematically remove duplication, clarify module boundaries, and make the codebase far easier to navigate and maintain.
