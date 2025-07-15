docs/sprints/current/SPRINT_12_REMAINING_WORK.md

In test/wanderer_notifier/http/middleware/rate_limiter_test.exs at line 8, the
ETS table name is hardcoded as :http_rate_limiter_buckets. To fix this, remove
the hardcoded value and instead call a function or use a module attribute from
the RateLimiter module that returns the table name, such as
RateLimiter.table_name(). This ensures consistency and avoids duplication of the
table name across the codebase.

In lib/wanderer_notifier/http/circuit_breaker_state.ex around lines 106 to 112,
the ETS table is created with :public access, allowing any process to write to
it and potentially causing inconsistent state. Change the access option from
:public to :protected so that only the owning GenServer process can write to the
table while other processes retain read access, ensuring safer state management.


lib/wanderer_notifier/http/circuit_breaker_state.ex (3)
34-36: Make circuit breaker thresholds configurable.

The failure threshold and recovery timeout are hardcoded, which limits flexibility. Consider making these configurable through application config or per-host settings.

50-56: Add error handling for ETS table access.

The function could crash if the ETS table doesn't exist (e.g., if called before GenServer initialization).

88-91: Document performance implications of get_stats.

Converting the entire ETS table to a list could be expensive with many tracked hosts.

lib/wanderer_notifier/http/middleware/rate_limiter.ex (2)
97-102: Extract duplicated host extraction logic to a shared utility module.

The extract_host/1 function is duplicated in both this module and WandererNotifier.Http.Middleware.Telemetry. Consider extracting this to a shared HTTP utilities module to follow DRY principles.

195-209: Consider handling HTTP date format in Retry-After header.

The Retry-After header can contain either seconds or an HTTP date. Currently, this only handles integer seconds.

lib/wanderer_notifier/http/client.ex (2)
154-154: Add error handling for JSON encoding.

The JsonUtils.encode! call can raise an exception for non-encodeable values, which would crash the request.

48-48: Fix incorrect default value for HTTP client module.

The default value :production is not a valid module name. It should default to a module, not an atom.

-@http_client_module Application.compile_env(:wanderer_notifier, :http_client, :production)
+@http_client_module Application.compile_env(:wanderer_notifier, :http_client, __MODULE__)