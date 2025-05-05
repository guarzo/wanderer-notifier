# Detailed Implementation Plan

Below is a step‐by‐step plan to refactor and reorganize the codebase.  All inline code references are escaped so you can copy the entire block as a single Markdown file.

---

## 1. Consolidate Behaviours

1. **Choose a single Behaviour interface**  
   - Decide on one module (e.g. `Notification`) that defines:  
     - `determine/1`  
     - `format/1`  
     - `deliver/1`  
2. **Rename and merge files**  
   - Rename `lib/wanderer_notifier/notifications/behaviour.ex` → `lib/wanderer_notifier/notifications/notification.ex`  
   - Delete `factory_behaviour.ex` and `interface.ex`  
3. **Update implementations**  
   - In each determiner, formatter, and notifier adapter:  
     - `@behaviour Notifications.Notification`  
     - Remove other `@behaviour …` lines  
4. **Refactor Factory/Dispatcher**  
   - Rename `notifications/factory.ex` → `notifications/dispatcher.ex`  
   - Change calls from `Notifications.Factory.dispatch/1` → `Notifications.Dispatcher.run/1`  
   - Inline simple logic if small enough  

---

## 2. Refactor Notifiers Helpers

1. **Merge Test Notifiers**  
   - Combine `notifiers/test.ex` and `notifiers/test_notifier.ex` into `lib/wanderer_notifier/notifiers/test_notifier.ex`  
   - Have it `@behaviour Notifications.Notifier` and implement `deliver/1`  
2. **Remove duplicate formatters**   
   - Remove contents of `notifications/formatters/…` and move the contents of lib/wanderer_notifier/notifiers/formatters to that location -- update imports and usage accordintgly


## 3. Configuration & Versioning

1. **Consolidate version logic**  
   - Move all version functions into `lib/wanderer_notifier/config/version.ex`  
   - In `config/config.ex`, call `Config.Version.version/0`  
2. **Standardize ENV loading**  
   - Replace custom `fetch!/1` + `parse_int/2` with Dotenvy  
   - Example:  
     ```elixir
     config :my_app, MyApp.Repo,
       port: {:system, "DB_PORT", 5432}
     ```  

---

## 6. API Layer Consistency

1. **Pick Plug and remove phoenix**  
   - Extract shared plugs into a single `ApiPipeline` module and import in each file  
2. **Extract common parsing/response**  
   - New `lib/wanderer_notifier/api/helpers.ex` with functions like `render_json/2`, `parse_body/1`  
   - Update controllers to one-liner actions  

---

## 7. CI / Scripts DRYness

1. **GitHub Actions**  
   - Create a single `.github/workflows/build_and_test.yml` with YAML anchors for shared steps  
   - Use `!include` or composite actions if needed  


---

### Verification & Rollout

- **Write or update tests** to cover behavior changes (especially for deduplication and scheduler)  
- **Code review & merge** one area at a time, verifying end-to-end functionality  
- **Release** with a clear changelog highlighting removed files and new module locations  

This plan will systematically remove duplication, clarify module boundaries, and make the codebase far easier to navigate and maintain.
