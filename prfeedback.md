In CLAUDE.md around lines 109 to 115, the list of feature flags is not properly
formatted according to markdown standards. Fix the formatting by ensuring each
list item starts with a hyphen followed by a space, and add blank lines before
and after the list to improve readability and consistency with markdown
conventions.

Outside diff range comments (5)
lib/wanderer_notifier/http.ex (1)
147-169: Move ZKillboard-specific functions to a dedicated module.

The get_killmail and build_url functions are specific to ZKillboard and don't belong in this generic HTTP module.

Consider moving these functions to a dedicated ZKillboard client module:

# lib/wanderer_notifier/killmail/zkillboard_client.ex

defmodule WandererNotifier.Killmail.ZKillboardClient do
alias WandererNotifier.HTTP

@doc """
Makes a GET request to the ZKill API for a specific killmail.
"""
def get_killmail(killmail_id, hash) do
url = build_url(killmail_id, hash)
HTTP.get(url)
end

defp build_url(killmail_id, hash) do
"https://zkillboard.com/api/killID/#{killmail_id}/#{hash}/"
end
end
lib/wanderer_notifier/api/controllers/dashboard_controller.ex (3)
32-543: Extract inline CSS to external stylesheets.

Having 500+ lines of inline CSS in a controller violates separation of concerns and makes the file difficult to maintain.

Move the CSS to external files:

Create priv/static/css/dashboard.css with all the styles
Serve static files through Plug.Static
Reference the stylesheet in the HTML head:
defp render_head do
"""

  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Wanderer Notifier Dashboard</title>
  <link rel="stylesheet" href="/css/dashboard.css">
  """
end
This will improve:

File organization and maintainability
Browser caching of styles
Development workflow (CSS hot reloading)
Code review efficiency
563-623: Extract inline JavaScript to external files.

Inline JavaScript should be moved to external files for better maintainability and browser caching.

Create priv/static/js/dashboard.js and reference it in the HTML:

<script src="/js/dashboard.js"></script>

Additionally, wrap the initialization code to ensure DOM is ready:

document.addEventListener('DOMContentLoaded', function() {
// Initialize dashboard functionality
initializeCountdown();
animateMetrics();
setupKeyboardShortcuts();
});
1-1124: Refactor large controller into smaller, focused modules.

This 1000+ line controller file is difficult to maintain and test. Consider breaking it down into smaller, focused modules.

Suggested structure:

# lib/wanderer_notifier_web/views/dashboard_view.ex

defmodule WandererNotifierWeb.DashboardView do
def render("dashboard.html", assigns) do # Use EEx templates
end
end

# lib/wanderer_notifier_web/views/dashboard/components.ex

defmodule WandererNotifierWeb.Dashboard.Components do
def system_overview_card(data), do: # ...
def websocket_status_card(data), do: # ...
def tracking_metrics_card(data), do: # ...

# etc.

end

# lib/wanderer_notifier_web/views/dashboard/formatters.ex

defmodule WandererNotifierWeb.Dashboard.Formatters do
def format_uptime(seconds), do: # ...
def format_time(datetime), do: # ...
end
This separation would improve:

Testability of individual components
Code reusability
Maintainability
Team collaboration
ideas.md (1)
1-641: Split this large document into focused, smaller documents.

This 600+ line document mixes different architectural concerns and levels of detail, making it difficult to navigate and maintain.

Consider splitting into separate documents:

docs/architecture/
├── current-state.md # Current architecture overview (sections 1-3)
├── improvement-areas.md # High-impact improvements (section 4)
├── implementation-roadmap.md # 6-week roadmap (section 5)
├── phoenix-migration.md # Phoenix/Ecto migration plan
├── quality-standards.md # QA strategy and standards
└── success-metrics.md # Performance and quality targets
This organization would:

Improve document discoverability
Enable focused discussions on specific topics
Make updates easier to track
Allow different team members to own different sections

In CLAUDE.md around lines 76 to 78, fix the formatting issues by ensuring proper
markdown syntax is used and add a missing blank line after the list to separate
it from the following content. Review the bullet points for consistent
indentation and spacing to meet markdown standards.
In README.md between lines 233 and 267, fix minor formatting issues in the
architecture section by ensuring consistent spacing and line breaks between list
items and headings. Adjust indentation and blank lines so that each numbered and
bulleted item is clearly separated and aligned properly for better readability
and to satisfy static analysis checks.

In lib/wanderer_notifier/api/controllers/system_info.ex around lines 185 to 197,
the format_connection_duration function currently formats durations in seconds,
minutes, and hours but does not handle durations of one day or more. To improve
clarity for very long durations, add a new function clause for seconds >= 86400
that calculates days and remaining hours, then returns a string formatted as "Xd
Yh". This will provide clearer output for durations like 168 hours by showing
"7d 0h" instead of "168h 0m".

In test/wanderer_notifier/http/middleware/circuit_breaker_test.exs around lines
42 to 44 and similarly at lines 62-64, 80-82, 98-100, 112-114, 132-134, 152-154,
179-181, and 207-209, replace the multiple Process.sleep(10) calls used to wait
for async state updates with a helper function that polls for the expected state
with a timeout. Implement a wait_for_state function that repeatedly checks the
circuit breaker state for the expected value, sleeping briefly between checks,
and halts early once the state matches or the timeout is reached. Use this
helper in place of Process.sleep to make the tests more robust and less prone to
flakiness.

In lib/wanderer_notifier/http/middleware/rate_limiter.ex around lines 132 to
149, the current use of the process dictionary for token bucket storage limits
rate limiting to individual processes and loses state on restarts, making it
unsuitable for production. Refactor this by replacing the process dictionary
with a more robust storage solution such as ETS for single-node deployments or
Redis for distributed environments. Alternatively, implement a GenServer to
manage the token bucket state centrally, ensuring shared, persistent, and
reliable rate limiting across processes and nodes.

In lib/wanderer_notifier/http/middleware/rate_limiter.ex around lines 173 to
187, the extract_retry_after function currently only handles Retry-After header
values as integer seconds. Update the function to also handle HTTP date formats
by attempting to parse the value as an HTTP date if integer parsing fails. If
the date parsing succeeds, calculate the milliseconds difference between that
date and the current UTC time, ensuring the result is not negative. If both
parsing attempts fail, default to returning 60,000 milliseconds (60 seconds).

In lib/wanderer_notifier/http/middleware/rate_limiter.ex around lines 159 to
165, the token refill calculation incorrectly uses min(time_diff \* refill_rate,
bucket.tokens + new_tokens), which does not properly compute the refill amount.
To fix this, calculate tokens_to_add as time_diff multiplied by refill_rate,
then update the bucket tokens by adding tokens_to_add to the current tokens,
capping the total at burst_capacity. Ensure burst_capacity is accessible in this
function either by passing it as a parameter or including it in the bucket
struct.

In lib/wanderer_notifier/http/middleware/retry.ex at line 95, the list of
retryable HTTP status codes is hardcoded directly in the pattern match. Replace
this hardcoded list with the existing module attribute that defines retryable
status codes to avoid duplication and maintain consistency. Update the pattern
match to reference the module attribute instead of the inline list.

In lib/wanderer_notifier/http/middleware/telemetry.ex around lines 114 to 116,
the current request ID generation uses :crypto.strong_rand_bytes which is
cryptographically strong but may be too costly for generating request IDs.
Replace it with a lighter-weight method such as :rand.uniform or
:erlang.unique_integer combined with Base encoding to generate sufficiently
unique but more performant request IDs.

In lib/wanderer*notifier/http/middleware/telemetry.ex around lines 277 to 280,
the calculate_body_size function calls Jason.encode! on maps without handling
potential JSON encoding errors, which can crash the middleware. Modify the
function to use Jason.encode instead of encode! and handle the {:ok, encoded}
and {:error, *} cases, returning the byte size on success and 0 on failure to
prevent crashes.

In lib/wanderer_notifier/http/middleware/telemetry.ex around lines 340 to 352,
the mask_sensitive_url function uses a broad rescue clause that catches all
errors, which can obscure real issues. Refactor the rescue block to catch only
specific exceptions related to URI parsing, such as URI.Error, to avoid hiding
other unexpected errors. This involves replacing the generic rescue with a
rescue clause that matches the specific error type.

In lib/wanderer_notifier/http/middleware/telemetry.ex around lines 290 to 296,
the function calculating response body size uses Jason.encode! which can raise
an error if the body is not JSON-encodable. Modify this to handle encoding
errors gracefully by using Jason.encode and pattern matching on the result to
avoid exceptions, returning 0 or a fallback size if encoding fails.

In lib/wanderer_notifier/http/circuit_breaker_state.ex lines 77 to 100, the
current can_execute?/1 function has a race condition because the state check and
transition from open to half-open are not atomic. To fix this, refactor
can_execute?/1 to make a synchronous GenServer.call that performs the state
check and transition atomically inside handle_call/3. Implement
handle_call({:can_execute, host}, \_from, state) to check the circuit state,
update it to half-open if the recovery timeout has passed, persist the updated
state in ETS, log the transition, and reply with the boolean result. This
ensures only one process can transition the state at a time, eliminating the
race condition.

In lib/wanderer_notifier/http/circuit_breaker_state.ex at lines 102 to 109, the
get_stats function converts the entire ETS table to a list, which can be costly
for large tables. Update the function's documentation to clearly state the
potential performance impact of this operation when many hosts are tracked,
advising caution or suggesting alternative approaches for large datasets.

In lib/wanderer_notifier/http/circuit_breaker_state.ex around lines 34 to 36,
the failure threshold and recovery timeout are hardcoded constants. Refactor
these values to be configurable by reading them from the application
configuration or allowing per-host overrides. Then update the code at lines 176
and 182 to use these configurable values instead of the hardcoded constants.

In lib/wanderer_notifier/http/circuit_breaker_state.ex around lines 50 to 56,
the get_state function accesses an ETS table without checking if the table
exists, which can cause a crash if the table is missing. To fix this, add error
handling to verify the ETS table's existence before lookup, such as using
:ets.info/1 to check if the table is present, and return a safe default or
handle the error gracefully if the table does not exist.

In lib/wanderer_notifier/http/client.ex around lines 149 to 152, the function
prepare_body uses JsonUtils.encode! which can raise exceptions on non-encodeable
values, risking a crash. Modify the code to handle potential encoding errors
gracefully by rescuing exceptions from JsonUtils.encode! and returning an
appropriate error or fallback value instead of letting the exception propagate.

In lib/wanderer_notifier/http/client.ex around lines 60 to 85, the code
duplicates body preparation and header merging in both test and production
branches of the request function. Refactor by moving the body preparation and
header merging before the case statement, so these steps are done once and their
results reused in both branches, eliminating duplication.

In lib/wanderer_notifier/http/client.ex around lines 60 to 85, the code calls
Application.get_env(:wanderer_notifier, :http_client) on every request, which
adds unnecessary overhead. To fix this, cache the HTTP client module value at
compile time or during application startup in a module attribute or a process
state. Then, use this cached value in the request function instead of calling
Application.get_env repeatedly. If runtime configuration changes are needed,
implement a GenServer to hold and update the cached value accordingly.

In lib/wanderer_notifier/http/client.ex around lines 161 to 165, the
default_middlewares function currently only includes Telemetry middleware, but
per project requirements, it should also include retry and rate limiting
middleware by default. Update the default_middlewares list to add the retry and
rate limiting middlewares alongside Telemetry to ensure automatic retries with
exponential backoff and rate limiting are handled centrally unless explicitly
overridden.

In sprint_plans.md around lines 19 to 23, the level-2 heading "## 🏃‍♂️ Sprint
1: HTTP Infrastructure Consolidation" lacks a blank line before it, causing
markdown linting errors. Add a blank line immediately before and after this
heading to comply with MD022 and improve readability.

In sprint_plans.md spanning lines 1 to 707, the entire multi-sprint plan is
contained in a single large markdown file, making it difficult to navigate and
maintain. To fix this, split the monolithic file into separate markdown files
for each sprint, such as docs/sprints/sprint_01.md through
docs/sprints/sprint_06.md, and create a short index file linking to each sprint
file. This restructuring will improve readability, ease reviews, reduce merge
conflicts, and help contributors focus on individual sprints without changing
any content.

In sprint_plans.md around lines 8 to 13, add a blank line before the numbered
list that follows the introductory sentence to fix the MD032 Markdown lint error
and improve readability. Repeat this adjustment throughout the document to
ensure all headings, paragraphs, and lists are separated by blank lines.

In sprint_plans.md lines 1 to 6, the title states "2-Week Sprint Plans" but the
metadata indicates a 12-week duration over 6 sprints, causing confusion. Update
the title to reflect the correct total duration or sprint count to match the
metadata. Additionally, add a blank line immediately after the level-1 heading
to comply with markdown formatting standards and avoid linting errors.

In lib/wanderer_notifier/http.ex around lines 39 to 41, the post_json function
currently calls post directly without encoding the body to JSON, which breaks
existing behavior. To fix this, modify post_json to encode the body to JSON
before passing it to post, ensuring the body is properly serialized as JSON for
the request.

In lib/wanderer_notifier/http.ex lines 96 to 130, the configure_middlewares
function builds the middleware list with multiple conditional reassignments and
a final check for an empty list that is redundant because the function always
returns a non-empty list. Simplify the function by directly constructing the
middleware list based on the presence of options without reassigning multiple
times, and remove the final empty list check, ensuring the default middlewares
are included when no specific options are provided.

In lib/wanderer_notifier/http.ex around lines 54 to 63, the mock client only
supports :get and :post HTTP methods, returning {:error, :method_not_supported}
for others. Extend the case statement to handle additional HTTP methods like
:put, :delete, :head, and :options by adding corresponding apply calls with
appropriate arguments for each method to fully support all common HTTP methods
in the mock client.

In lib/wanderer_notifier/api/controllers/dashboard_controller.ex at lines 679,
806, and 1106, dynamic content is rendered directly without HTML escaping,
risking XSS vulnerabilities. Define a helper function html_escape/1 that
replaces special characters with their HTML entities as described, then wrap all
dynamic content outputs like data.server_version with this helper before
rendering. This ensures all dynamic content is safely escaped. Consider
migrating to a templating engine like EEx for automatic escaping in the future.

In sprint1.md around lines 108 to 131, add a new section titled "Rollback
Strategy" after the existing sections. Include points about using a feature flag
to toggle between old and new HTTP clients, maintaining backward compatibility
during migration, retaining old HTTP client code for at least one sprint
post-migration, documenting the rollback procedure with clear steps, and testing
the rollback process before production deployment. This will provide a clear
plan for safe deployment and quick recovery if issues arise.

In sprint1.md between lines 60 and 107, the sprint plan is missing explicit task
dependencies and some time estimates are too optimistic. Add a "Task
Dependencies" section listing dependencies between tasks 1.1 through 1.6 as
suggested, and update the time estimates for Task 1.4 to 4-5 days and Task 1.6
to 5 days. Additionally, include a section outlining risk mitigation strategies
for potential delays in tasks to improve planning and tracking.

In sprint1.md lines 1 to 6, fix markdown formatting issues by ensuring
consistent spacing after headers and between sections, using proper bold syntax
without extra spaces, and maintaining line breaks for readability. Adjust the
markdown so that headers and bold text render correctly and the document appears
clean and well-structured.
In ideas.md around lines 608 to 627, add a new section titled "Monitoring
Strategy" after the success metrics to define how these metrics will be tracked
and acted upon. Include details on tools like Prometheus and Grafana for
visualization, PagerDuty for alerts, weekly SLO reviews, and incident response
runbooks. Also add an "Alert Thresholds" subsection specifying warning and
critical levels for key metrics such as cache hit rate, WebSocket uptime, memory
growth, and error rate to make the metrics actionable.

In ideas.md around lines 296 to 303, the validate_attackers_present function
uses length/1 which is inefficient; replace it with a more efficient check like
Enum.empty?/1 to verify presence of attackers. Update the error message to be
more specific. Additionally, implement new validations to ensure exactly one
attacker has final_blow set to true, all damage values are non-negative, and
timestamps are not set in the future.
