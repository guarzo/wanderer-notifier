## Detailed Refactoring Plan

Below is a step-by-step roadmap to implement each of the five refactorings. Each step is broken down into small tasks suitable for a junior developer.

---

### 1. Standardize Naming Conventions

1. **Audit existing usage**

   - Grep for acronym variants:
     ```bash
     grep -R -E '\b(ESI|esi|ZKill|zkill)\b' lib/
     ```
   - List all modules/functions that use each variant.

2. **Choose a style**

   - **Option A:** PascalCase for modules (`ESI`, `ZKill`) and snake_case for variables (`esi_data`, `zkill_recent`).
   - **Option B:** All-lowercase acronyms (`esi`, `zkill`) everywhere.

3. **Rename modules/functions**

   - In `lib/…/esi/` folder, update `defmodule WandererNotifier.ESI.Service` → `WandererNotifier.Esi.Service` (or vice versa).
   - In `lib/…/killmail/zkill_client.ex`, rename `ZKillClient` → `ZkillClient` (or vice versa).
   - **Tip:** Use `mix format —check-formatted` and your editor’s refactor-rename to catch references.

4. **Unify behaviour suffix**

   - Pick one: `…Behaviour` or `…Behavior`.
   - Rename files under `lib/.../behaviour.ex` to match (e.g. `cache_behaviour.ex` → `cache_behavior.ex`).
   - Update all `@behaviour …` annotations accordingly.

5. **Run tests & fix fallout**
   - `mix test` → fix any compile errors.
   - Update docs and READMEs to reflect new names.

---

### 2. Extract Shared Controller Logic

1. **Create a new file for the macro**

   - Path: `lib/wanderer_notifier_web/controllers/controller_helpers.ex`
   - Define:

     ```elixir
     defmodule WandererNotifierWeb.ControllerHelpers do
       defmacro __using__(_) do
         quote do
           import Plug.Conn
           import unquote(__MODULE__), only: [send_error: 3]
           # fallback for unmatched routes
           def match(conn), do: send_error(conn, 404, "not_found")
         end
       end

       def send_error(conn, status, msg) do
         conn
         |> put_status(status)
         |> json(%{error: msg})
         |> halt()
       end
     end
     ```

2. **Update each controller**

   - At the top of `lib/.../kill_controller.ex` (and others), replace:
     ```elixir
     import Api.Helpers
     match _ do …
     ```
     with:
     ```elixir
     use WandererNotifierWeb.ControllerHelpers
     ```

3. **Remove duplicates**

   - Delete any private `send_error/3` or fallback `match _` definitions.

4. **Verify behavior**
   - Run `mix test` and manually hit an endpoint to confirm errors still render correctly.

---

### 3. Refactor Nested `case` Blocks into `with`

1. **Identify nested `case` usages**

   - Grep for `case` inside `case` in controllers:
     ```bash
     grep -R "case .* do" lib/.../controllers
     ```

2. **Refactor one example**

   - Original:
     ```elixir
     case Integer.parse(id_str) do
       {id, ""} ->
         case Repo.get(Kill, id) do
           nil -> send_error(conn, 404, "not found")
           kill -> send_success(conn, kill)
         end
       :error -> send_error(conn, 400, "invalid id")
     end
     ```
   - New:
     ```elixir
     with {id, ""} <- Integer.parse(id_str),
          %Kill{} = kill <- Repo.get(Kill, id) do
       send_success(conn, kill)
     else
       :error            -> send_error(conn, 400, "invalid id")
       nil               -> send_error(conn, 404, "not found")
       {:error, reason}  -> send_error(conn, 500, reason)
     end
     ```

3. **Apply to all controllers**

   - Repeat the pattern for each nested `case`.

4. **Add tests**
   - For each refactored action, add a test for each branch (`:error`, `nil`, success).

---

### 4. Generate Cache-Key Functions via Macro

1. **Define a macro generator**

   - In `lib/wanderer_notifier/cache/keys.ex`, replace manual defs with:

     ```elixir
     defmodule WandererNotifier.Cache.Keys do
       @prefix_map "map:"
       @entity_system "system"
       @entity_character "character"
       # … other prefixes/entities

       defmacro defkey(name, prefix, entity) do
         quote do
           def unquote(name)(id, extra \\ nil) do
             base = "#{unquote(prefix)}#{unquote(entity)}:#{id}"
             if extra, do: "#{base}:#{extra}", else: base
           end
         end
       end

       # Generate functions:
       defkey :system,    @prefix_map,       @entity_system
       defkey :character, @prefix_map,       @entity_character
       # … etc.
     end
     ```

2. **Remove old definitions**

   - Delete all manually written `def system/2`, `def character/2`, etc.

3. **Compile & test**
   - `mix compile && mix test` to confirm macros generate correct functions.

---

### 5. Trim Custom Cachex Boilerplate

1. **Locate custom wrappers**

   - Find `Cache.CachexImpl` and note methods that simply wrap `Cachex.put/3`, `Cachex.get/2`, etc.

2. **Replace calls**

   - In modules using `Cache.CachexImpl`, change:
     ```elixir
     Cache.CachexImpl.put(key, value, ttl)
     ```
     to:
     ```elixir
     Cachex.put(:my_cache, key, value, ttl: :timer.seconds(ttl))
     ```

3. **Remove custom code**

   - Delete `lib/wanderer_notifier/cache/cachex_impl.ex` and its tests.

4. **Adjust supervision tree**

   - Ensure `Cachex` is started in `application.ex`:
     ```elixir
     children = [
       {Cachex, name: :my_cache, expiration: expiration_opts()},
       …
     ]
     ```

5. **Run full test suite**
   - `mix test` and manually validate TTL behavior in iex.

---

### 6. Review UI in ./renderer

1 - ensure functionality works

**After all steps:**

- Run `mix format` and `mix credo —strict`.
- Update README to document the new helper macro and cache setup.
- Consider adding a CI check for naming conventions if desired.

Let me know if you need any code samples or further details on any sub-step!
