# Refactoring Plan

## 1. Refactoring `lib/wanderer_notifier/notifiers/helpers`

### a) Consolidate Deduplication

You currently have two competing deduplication modules:

- **ETS-based:** `Notifiers.Helpers.Deduplication`
- **Cachex-based:** `Helpers.DeduplicationHelper`

**Recommendation:**

- **Pick one backend** (ETS or Cachex) to be your sole dedup store.
- **Collapse both** into a single module under:
  - `lib/wanderer_notifier/notifications/helpers/deduplication.ex`
- All determiners & formatters should share the same TTL and error handling.
- **Rename** to `Notifications.Helpers.Deduplication` (dropping the Notifiers prefix).
- **Expose a clear API**, for example:

```elixir
@spec check(type :: :system | :character, id :: String.t() | integer()) ::
  {:ok, :new | :duplicate} | {:error, term()}
```

This removes confusion about where duplicate checks live and ensures every part of the pipeline uses the same logic.

---

### b) Give "Test" Its Own Adapter

- `TestNotifications` currently lives in `notifiers/helpers` but is really a Notifier adapter (i.e., an implementation of your notifier behaviour), not a helper.

**Recommendation:**

- Move to: `lib/wanderer_notifier/notifiers/test_notifier.ex`
- Rename to: `TestNotifier`
- Have it `@behaviour Notifier` and implement `deliver/1` (or your unified notifier callback).
- Pull out any utility functions it currently redefines (e.g., `ensure_list`, `_perform_system_cache_verification`) into shared modules:
  - Either into the consolidated dedup helper
  - Or into a new `Notifications.Helpers.CacheVerification` module

---

### c) Split Out Miscellaneous Bits

- Any other loose functions in `notifiers/helpers` (e.g., embed-field builders, retry logic, image extractors) should each live in a purpose-named module under either:
  - `lib/wanderer_notifier/notifiers/formatters/...` (for anything that shapes payloads)
  - `lib/wanderer_notifier/notifiers/transport/...` (for HTTP/webhook helpers)

**Goal:**

- Each helper directory is tiny and focused: one module per single responsibility.

---

## 2. Reshaping `lib/wanderer_notifier/utilities`

You've amassed a grab-bag of both generic and domain-specific helpers:

| Generic Helpers                         | Domain-Specific Helpers                   |
| --------------------------------------- | ----------------------------------------- |
| `ListUtils.ensure*list/1`               | `CharacterUtils.extract**`                |
| `MapUtil.get_value/2`                   |                                           |
| `Utilities.Debug` (map-client triggers) |                                           |
| `NumberHuman.number*to_human/1`         | any ESI-or-Killmail helpers embedded here |
| `TimeHelpers.format**`                  |                                           |
| `TypeHelpers.typeof/1`                  |                                           |
| `DateTimeUtil.parse_datetime/1`         |                                           |

### a) Split Generic vs. Domain

- Move truly generic modules into `lib/wanderer_notifier/utils/` (or even extract to a standalone hex package):
  - `ListUtils`, `MapUtil`, `NumberHuman`, `TimeHelpers` / `DateTimeUtil`
- Relocate domain-centric utilities into their respective contexts:
  - `CharacterUtils` → `lib/wanderer_notifier/notifications/formatters/character_helpers.ex`
  - ESI, Killmail, Cache-verification helpers → `lib/wanderer_notifier/map/...` or `lib/wanderer_notifier/killmail/...`

**Result:**

- Clear "I'm just a utility" boundary vs. "I belong in your domain pipeline."

### b) Lean on Battle-Tested Libs

- Consider using `Timex` or `Calendar.strftime` directly instead of rolling your own uptime parser (`TimeHelpers.format_uptime/1`).
- If you only need simple atom-map conversion, `Map.new/2` plus pattern-matching can replace a custom `atomize_keys/2`.

### c) Ensure Naming Consistency

- Stick to the `*Utils` or `*Helpers` suffix for all modules in the utils folder.
- Keep module names and file paths in sync:
  - e.g., `Utilities.DateTime` → `date_time.ex` (or merge into `DateTimeUtil` if that's your chosen style).

**By doing this you'll end up with:**

- A single, unambiguous deduplication module everyone uses.
- Notifier adapters clearly living in `notifiers/` by implementation, not helper-land.
- A `utils/` directory that holds only pure, context-free functions—everything else lives in its appropriate feature area.

---

## 3. Structured Formatter

- The version of structured formatter that is currently in use seems to have lost a great deal of its functionality.
- The original version is at the project root, but is using old imports and old structure.

**Recommendation:**

- Update the version in use to make use of the message formats from the original.
