test/wanderer_notifier/http/middleware/rate_limiter_test.exs (1)
36-37: Remove burst_capacity option from tests

The burst_capacity option is no longer supported in the Hammer-based implementation and should be removed from test cases.

Apply this diff to remove the obsolete burst_capacity option:

        build_request(

-          [per_host: true, requests_per_second: 1, burst_capacity: 1],

*          [per_host: true, requests_per_second: 1],
            "https://api1.example.com/test"
          )
  Similar changes should be made to lines 42 and other test cases using burst_capacity.

lib/wanderer_notifier_web/controllers/dashboard_controller.ex (1)
21-605: Extract HTML rendering to Phoenix templates for better maintainability.

Embedding 580+ lines of HTML, CSS, and JavaScript directly in the controller violates separation of concerns and makes the code difficult to maintain. Consider using Phoenix templates or LiveView.

Instead of inline HTML generation, consider:

Create a template file lib/wanderer_notifier_web/templates/dashboard/index.html.heex
Move CSS to assets/css/dashboard.css
Move JavaScript to assets/js/dashboard.js
Use Phoenix.HTML helpers for dynamic content
This would make the code more maintainable, enable better syntax highlighting, and allow for asset optimization through the Phoenix asset pipeline.

lib/wanderer_notifier/killmail/websocket_client.ex (1)
63-63: Consider more robust connection ID generation.

The current approach using :erlang.phash2(self()) could theoretically have collisions. Consider using a combination of timestamp and random values for guaranteed uniqueness:

-connection*id = "websocket_killmail*#{:erlang.phash2(self())}"
+connection*id = "websocket_killmail*#{System.system*time(:millisecond)}*#{:rand.uniform(1_000_000)}"

In lib/wanderer_notifier/event_sourcing/event.ex at line 148, the age
calculation uses System.system_time(:millisecond), which can be inaccurate if
the system clock changes. To fix this, switch to using
System.monotonic_time(:millisecond) for calculating the age difference to ensure
monotonicity. Keep using system time only for absolute timestamps. If needed,
modify the event struct to store both system and monotonic timestamps to support
this change.

In lib/wanderer_notifier_web/channels/user_socket.ex at lines 5-6, the connect/3
function currently allows all connections without authentication. Modify it to
validate client credentials using Phoenix.Token or session cookies, and if
valid, assign the authenticated user to the socket with assign(socket,
:current_user, user); otherwise, return :error. Additionally, in
lib/wanderer_notifier_web/channels/map_channel.ex and killmail_channel.ex,
update the join/3 functions to check that socket.assigns.current_user is
authorized to join the requested topic, enforcing user-specific permissions
before allowing channel subscription.

In lib/wanderer_notifier/http/client.ex around lines 214 to 219, the rate
limiting middleware was removed from the default middleware chain to avoid
startup issues. Now that the Hammer library migration is complete and properly
configured, re-enable the rate limiting middleware by adding it back into the
default middleware list alongside Telemetry and Retry. Ensure the order respects
any dependencies or priorities required by the middleware.

In lib/wanderer_notifier/http/client.ex between lines 150 and 189, the timeout
options handling in build_req_opts is flawed because both :timeout and
:recv_timeout keys map to :receive_timeout, causing one to overwrite the other.
To fix this, adjust the logic to prioritize one timeout option over the other or
merge them properly so that only one :receive_timeout key is set in req_opts,
ensuring the correct timeout value is used without overwriting.

In lib/wanderer_notifier/http/middleware/rate_limiter.ex around lines 86 to 91,
there is commented-out debug logging code that should be cleaned up. Remove the
commented AppLogger.api_info block entirely or implement conditional logging
that only activates this debug information when the log level is set to debug,
to keep the codebase clean and maintainable.

In scripts/test_telemetry.exs from lines 1 to 64, the telemetry test script
lacks error handling and verification of module availability, which could cause
runtime failures if modules or functions are missing. To improve robustness, add
checks to confirm that the WandererNotifier.Telemetry and
WandererNotifier.Core.Stats modules and their expected functions exist before
calling them. Also, wrap telemetry calls in try-rescue blocks to gracefully
handle any unexpected errors during testing, ensuring the script completes and
reports issues without crashing.

\
In lib/wanderer_notifier/map/clients/systems_client.ex around lines 116 to 147,
the batch size for processing systems is hardcoded to 50. To improve
flexibility, refactor the code to make the batch size configurable by adding a
module attribute or configuration parameter for batch size, then use that value
instead of the fixed 50. This allows adjusting batch size without code changes.

In lib/wanderer_notifier/map/clients/systems_client.ex lines 149 to 162, replace
the use of list concatenation (++) in the recursive call with list prepending to
improve performance. Instead of appending processed_batch to accumulated using
++, prepend processed_batch to accumulated using the cons operator, and then
reverse the accumulated list once in the base case to maintain the correct
order. This change reduces the time complexity from O(n²) to O(n).

In lib/wanderer_notifier/map/clients/characters_client.ex between lines 155 and
169, the function process_characters_in_batches uses list concatenation
(accumulated ++ processed_batch) which causes O(n²) complexity. To fix this,
change the accumulator to build the list in reverse order by prepending
processed_batch to accumulated, then reverse the final accumulated list once all
batches are processed. This avoids repeated list concatenations and improves
performance.

In scripts/memory_monitor.exs between lines 131 and 173, the current code checks
if the module is an atom before calling Process.whereis, but since all entries
are atoms or modules, simplify by directly calling Process.whereis on each
module without the conditional. Additionally, refactor the hardcoded alert
thresholds for memory and message queue length into configurable variables or
parameters so they can be easily adjusted without modifying the code.

In lib/wanderer_notifier/application.ex lines 144 to 162, replace the hardcoded
Process.sleep(1000) with a proper readiness check for the GenServers to avoid
race conditions. Implement a function like wait_for_genservers/1 that actively
checks if the required GenServers are started and ready, similar to the existing
wait_for_supervisor_startup/0 function, and call this function before proceeding
with initialization.

In lib/wanderer_notifier/notifications/license_limiter.ex around lines 57 to 67,
the background task that increments the notification count currently rescues
errors silently without logging. Modify the rescue block to log the error
details using an appropriate logger, so unexpected errors are recorded for
debugging while keeping the task non-blocking.

In lib/wanderer_notifier/realtime/health_checker.ex around lines 85 to 110, the
uptime calculation currently uses fixed percentages instead of actual connection
history. To fix this, implement tracking of disconnect events with timestamps in
the connection state, then update calculate_uptime_from_connection_time to
compute uptime based on the real connected and disconnected durations rather
than fixed values. This will provide accurate uptime metrics reflecting true
connection behavior.

In lib/wanderer_notifier/killmail/websocket_client.ex around lines 335 to 354,
the retry logic after a failed join_channel attempt uses a fixed 5-second delay,
which can cause repeated rapid retries on persistent failures. Modify the retry
mechanism to implement exponential backoff by increasing the delay interval
progressively with each retry attempt, resetting it upon success. This can be
done by tracking the retry count in the state and calculating the delay as a
function of this count before calling Process.send_after.
