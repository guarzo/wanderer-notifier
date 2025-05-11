In lib/wanderer_notifier/api/helpers.ex at line 34, the parse_body function
assumes that Plug.Parsers middleware has already parsed the body, which may not
always be true. Modify the function to check if conn.body_params is populated
and handle cases where it is not, either by returning an error tuple or a
default value, to make the function more robust against unparsed request bodies.

In index.md at line 59, the environment variable name WANDERER_MAP_URL_WITH_NAME
is inconsistent with the .env.template file where it is named WANDERER_MAP_URL.
Update the variable name in index.md to WANDERER_MAP_URL to ensure consistency
across all documentation and configuration files.

In index.md around lines 72 to 75, there are multiple consecutive blank lines
that violate Markdown formatting standards. Remove the extra blank lines so that
only a single blank line remains between paragraphs or sections to ensure proper
Markdown rendering.

In config/config.exs at line 81, update the logger configuration to replace the
module name "WandererNotifier.Config.Config" with the new module name
"WandererNotifier.Config" to reflect the renaming and ensure correct log level
application.

In README.md at line 158, the environment variable name
`WANDERER_MAP_URL_WITH_NAME` is inconsistent with the `.env.template` where it
is `WANDERER_MAP_URL`. Update the README.md to use `WANDERER_MAP_URL` to keep
the variable name consistent across all documentation and configuration files.

In the .env.template file at line 7, rename the environment variable from
WANDERER_MAP_URL to WANDERER_MAP_URL_WITH_NAME to ensure consistency with its
usage in index.md and README.md. Update the variable name while keeping the
comment intact.

In config/test.exs around lines 4 to 7 and also lines 44 to 47, there are
duplicate configurations for :env and :test_env keys under :wanderer_notifier
which can cause confusion as the last one overrides the previous. Consolidate
these duplicate keys into a single configuration block to maintain clarity and
avoid unintentional overrides, ensuring all related settings are grouped
together in one place.

In config/test.exs around lines 40 to 52, the console logger is configured
twice, causing the first format setting to be overwritten by the second. To fix
this, combine both console logger configurations into a single config call or
add `merge: true` to the second config call to explicitly merge the settings
instead of replacing them.

In config/test.exs around lines 34 to 35, the esi_service is hard-coded to
WandererNotifier.ESI.ServiceMock while character_tracking_enabled and
system_tracking_enabled flags are both true, which can mask integration issues.
Fix this by either disabling the upstream-dependent flags
(character_tracking_enabled and system_tracking_enabled) when using the mock
service or wrap the configuration in a conditional that checks if EXTERNAL_TESTS
environment variable is true, using the real ESI service and enabling the flags
only in that case, and otherwise using the mock service with flags disabled or
adjusted accordingly.

In lib/wanderer_notifier/api/controllers/notification_controller.ex lines 43 to
59, the function get_notification_settings/1 has an unused parameter \_conn,
which is misleading. Remove the parameter from the function definition and
update all calls to use get_notification_settings() without arguments.
Additionally, replace Exception.format_stacktrace(**STACKTRACE**) with
Exception.format_stacktrace(**STACKTRACE**, []) to avoid deprecation warnings in
Elixir 1.15.

In lib/wanderer_notifier/api/controllers/kill_controller.ex around lines 39 to
42, the /kills endpoint does not handle errors from
cache_module().get_latest_killmails(), causing error tuples to be returned as
HTTP 200 with JSON bodies. Update the code to pattern match on the result of
get_latest_killmails(), sending a successful response with the killmails list on
{:ok, kills} and sending an appropriate error response with a non-200 status
code when {:error, reason} is returned.

In lib/wanderer_notifier/api/controllers/kill_controller.ex around lines 50 to
53, the case statement redundantly wraps the successful result from
Processor.get_recent_kills/0 in an additional {:ok, ...} tuple, causing nested
tuples like {:ok, {:ok, kills}}. Remove the wrapping by returning the result
directly without adding {:ok, ...} to simplify the code and avoid double
wrapping.

In lib/wanderer_notifier/api/controllers/kill_controller.ex around lines 8 to
15, the cache_module function uses Application.get_env/3 which performs a
runtime lookup on every call. To improve performance, replace
Application.get_env/3 with Application.compile_env/3 so the configuration is
fetched once at compile-time, eliminating repeated ETS lookups during runtime.

In lib/wanderer_notifier/api/controllers/web_controller.ex at lines 1 to 4, the
@moduledoc still describes the module as "Controller for debug-related
endpoints" which is misleading since the module is now named WebController.
Update the @moduledoc to accurately describe the current purpose and scope of
the WebController, reflecting its broader responsibilities beyond just debug
endpoints.

In lib/wanderer_notifier/api/controllers/web_controller.ex around lines 151 to
158, the code uses the deprecated Exception.format_stacktrace/1 function.
Replace Exception.format_stacktrace(**STACKTRACE**) with
Exception.format(:error, error, **STACKTRACE**) to properly format the
stacktrace along with the error for compatibility with Elixir 1.16 and later.

In lib/wanderer_notifier/api/controllers/web_controller.ex around lines 86 to
97, the scheduler lookup compares the path parameter with the scheduler name in
a case-sensitive manner, which can cause 404 errors due to capitalization
mismatches. To fix this, normalize both the incoming path parameter and the
scheduler names by converting them to lowercase using String.downcase/1 before
comparison. This ensures case-insensitive matching and prevents unnecessary 404
errors.

In lib/wanderer_notifier/cache/behaviour.ex around lines 75 to 78, the functions
get_recent_kills/0 and init_batch_logging/0 are marked as optional callbacks but
still appear in the main callback list. Remove these two functions from the main
callback list and keep them only in the @optional_callbacks attribute to ensure
Dialyzer does not treat their absence as an error.

In lib/wanderer_notifier/cache/behaviour.ex around lines 39 to 41, the callback
set/3 has a redundant and inconsistent return type list including both :ok and
{:ok, value()}. To fix this, choose a single consistent return type convention
for set/3, put/2, delete/1, and clear/0—either :ok or {:ok, value()}—and update
their @callback definitions accordingly to ensure predictable contract behavior.

In lib/wanderer_notifier/cache/behaviour.ex around lines 61 to 62, the @callback
specification for get_and_update/2 incorrectly states that the update function
returns {value(), value()} where the first is the current value and the second
is the new value. According to Cachex semantics, the update function should
return {new_value, return_value}. Review your implementation to confirm which
order it follows, then update the @callback spec to match Cachex's expected
{new_value, return_value} tuple format or adjust the implementation to follow
the documented contract, ensuring consistency to prevent data corruption.

In lib/wanderer_notifier/application.ex around lines 88 to 98, the code sets the
global compiler option ignore_module_conflict to true but does not revert it
afterward, which can suppress legitimate warnings elsewhere. To fix this,
capture the current compiler options before setting ignore_module_conflict to
true, then after reloading the modules, restore the original compiler options by
calling Code.compiler_options with the saved options.

In lib/wanderer_notifier/application.ex around lines 41 to 47, the current code
conditionally appends to the children list by reassigning it with a new list,
causing unnecessary list reallocation and shadowing. Refactor this by either
using List.insert_at/3 to insert the scheduler supervisor into the existing
children list without recreating it or restructure the code to build the
children list in a single pass, avoiding reassignment and improving clarity.

In lib/wanderer_notifier/application.ex around lines 29 to 31, the metric
registry is initialized outside the supervision tree, which risks losing it if
it crashes. To fix this, move the initialization of
WandererNotifier.Killmail.MetricRegistry into the application's supervision
children list or supervise it as a Task child, ensuring it is restarted
automatically on failure.

In config/runtime.exs around lines 12 to 13, the current code unconditionally
overrides existing environment variables with values from the .env file, which
can shadow production secrets. Modify the Enum.each call to only set the
environment variable if it is not already present in the system environment,
preserving the precedence of real runtime environment variables over .env
defaults.

In config/runtime.exs around lines 16 to 31, the parse_bool function currently
uses multiple string comparisons to determine boolean values, which is
inefficient. Refactor this function to use a map as a lookup table that maps
lowercase string values to booleans, returning the default if the key is not
found. This change will simplify the code, reduce branching, and provide
constant-time lookup while maintaining the same behavior.

In cicd.txt lines 1 to 214, the file currently contains mixed design notes and
clipboard artefacts that are confusing and not executable. To fix this, move the
content to a proper documentation file such as docs/ci-cd.md and clearly mark it
as documentation, or delete cicd.txt entirely once the workflows are
implemented. This will prevent confusion and keep the project root clean.

In lib/wanderer_notifier/cache/cachex_impl.ex around lines 28 to 33, the current
code returns {:error, :not_found} on a cache miss, which conflates a missing key
with an actual error. Modify the code to return {:ok, nil} instead for cache
misses to align with Cachex's native behavior. This change allows downstream
code to differentiate between a cache miss and an error without needing to
rescue every lookup. If callers require :not_found, they should handle that
conversion at the call site.

In lib/wanderer_notifier/cache/cachex_impl.ex around lines 50 to 56, the TTL
value is only checked for nil but not validated for negative or non-integer
values, which can cause errors in Cachex. Add validation to ensure TTL is a
positive integer before converting it with :timer.seconds. If TTL is invalid,
handle it gracefully by either defaulting to no TTL or returning an error,
preventing invalid TTLs from being passed to Cachex.put.

In lib/wanderer_notifier/cache/cachex_impl.ex around lines 132 to 141, the
current code uses an anonymous function that simply forwards its argument to
update_fun/1, duplicating logic unnecessarily. Refactor the call to
Cachex.get_and_update/3 by delegating directly to update_fun without wrapping it
in another anonymous function, reducing code duplication while maintaining
atomicity.

In .github/workflows/build_and_test.yml around lines 27 to 39, the use of YAML
anchors (x-checkout-cache) is not supported by GitHub Actions and will cause
workflow rejection. Replace this anchor-based reuse with GitHub Actions native
reusable workflow features by converting the steps under x-checkout-cache into a
composite action stored in .github/actions/, then reference this composite
action in your workflow using the uses keyword. Alternatively, consider using
workflow templates or matrix strategies, but the preferred fix is to create and
call a composite action for these common checkout and cache steps.

In .github/workflows/build_and_test.yml at lines 87, 123, 157, 217, 251, and
285, update the GitHub checkout action version from v3 to v4 to use the latest
version with improved performance and reliability. Replace all instances of
"actions/checkout@v3" with "actions/checkout@v4" throughout the file.

In .github/workflows/build_and_test.yml at lines 193 to 194, replace the
hard-coded placeholder values for MAP_TOKEN and DISCORD_CHANNEL_ID with
references to GitHub Actions secrets. Update the workflow to use the syntax for
accessing secrets (e.g., ${{ secrets.MAP_TOKEN }}) and ensure these secrets are
configured in the repository settings under Secrets before running the workflow.

In .github/workflows/build_and_test.yml around lines 107 to 113, remove the
continue-on-error: true setting from the compilation and test coverage steps to
ensure that any warnings or coverage failures cause the build to fail. This
change will prevent important issues from being overlooked by making these steps
critical to the build success. Also, review the credo step at line 147 and
remove continue-on-error: true there unless there is a specific reason to allow
failures.

In .github/workflows/build_and_test.yml lines 1 to 25, update the workflow name
to be more descriptive by removing "(DRY)" and choose a clear, user-friendly
name. Also, remove the paths-ignore entry for "mix.exs" under the push event so
that changes to this file trigger the workflow, ensuring dependency updates
cause builds.

In .github/workflows/build_and_test.yml around lines 79 to 85, there are
duplicate environment variables for the Discord bot token and cache directory.
Remove the redundant variables by keeping only one instance of each (e.g., keep
either DISCORD_BOT_TOKEN or WANDERER_DISCORD_BOT_TOKEN, and either CACHE_DIR or
WANDERER_CACHE_DIR) to consolidate and avoid duplication.

In lib/wanderer_notifier/cache/keys.ex at lines 561 to 562, the system_key
function is redundant because it only calls the system/1 function without adding
any new behavior. Remove the system_key function to reduce unnecessary API
surface unless there is a documented reason to keep it as an alias.

In lib/wanderer_notifier/cache/keys.ex at lines 111 to 113, the
tracked_character function uses direct string interpolation for the key format,
unlike other functions that use the join_parts helper. To fix this
inconsistency, refactor the tracked_character function to build the key using
the join_parts helper with the appropriate parts instead of string
interpolation, ensuring uniform key formatting across the module.

In lib/wanderer_notifier/config/config.ex around lines 210 to 215, the
base_map_url function assumes the URL is always well-formed, which can cause
failures with unexpected URL formats. To fix this, add validation to check if
the parsed URI has a valid scheme and host before constructing the base_url.
Handle cases where these components are missing by returning a safe default or
an error, ensuring the function does not crash on malformed URLs.

In lib/wanderer_notifier/config/config.ex around lines 51 to 56, the map_slug
function assumes the URL is always valid and has a path, which can cause
failures if the URL is nil or malformed. To fix this, add checks to handle nil
or empty URLs gracefully, and ensure the URI parsing and path extraction safely
handle unexpected formats by using conditional logic or pattern matching to
avoid runtime errors.
