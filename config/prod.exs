import Config

# Production logger configuration - optimized for performance and structured logging
config :logger,
  level: :info,
  backends: [:console]

# Console logger configuration with structured format for production
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :category],
  # Disable colors in production
  colors: [enabled: false]

# Module-specific log levels for production - optimized to reduce noise
config :logger, :module_levels, %{
  # Core processing - reduced verbosity
  "WandererNotifier.Killmail.Pipeline" => :warning,
  "WandererNotifier.Killmail.WebSocketClient" => :warning,
  "WandererNotifier.Map.SSEClient" => :warning,

  # External service integrations - only errors
  "WandererNotifier.ESI.Client" => :error,
  "WandererNotifier.Http.Client" => :warning,
  "WandererNotifier.License.Service" => :warning,

  # Cache and performance - minimal logging
  "WandererNotifier.Cache" => :warning,
  "WandererNotifier.Cache.Analytics" => :error,
  "WandererNotifier.Cache.PerformanceMonitor" => :error,

  # Notifications - important for monitoring
  "WandererNotifier.Notifications" => :info,
  "WandererNotifier.Notifiers.Discord" => :info,

  # Configuration and startup - keep visible
  "WandererNotifier.Config" => :info,
  "WandererNotifier.Application" => :info
}

# Production-specific Phoenix endpoint configuration
config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  # Enable compression for better performance
  http: [
    compress: true,
    protocol_options: [
      idle_timeout: 60_000,
      max_connections: 16_384,
      max_keepalive: 100
    ]
  ],
  # Disable debug errors in production
  debug_errors: false,
  # Enable code reloading in development only
  code_reloader: false,
  # Disable watchers in production
  watchers: [],
  # Enable static cache headers
  static_url: [path: "/static"],
  cache_static_manifest: "priv/static/cache_manifest.json",
  # Server configuration
  server: true

# Configure Cachex for production optimization
config :cachex,
  # Default cache settings optimized for production
  default: [
    # Memory limits and cleanup
    limit: 10_000,
    expiration: %{
      default: :timer.hours(24),
      interval: :timer.minutes(30),
      lazy: true
    },
    # Disable statistics collection for performance
    stats: false,
    # Enable compression for memory efficiency
    compression: [
      threshold: 1024
    ]
  ]

# Production telemetry configuration
config :telemetry,
  # Reduce telemetry overhead
  handlers: [
    # Keep essential metrics only
    {WandererNotifier.Telemetry, :handle_event, [:cache, :analytics]},
    {WandererNotifier.Telemetry, :handle_event, [:http, :request]},
    {WandererNotifier.Telemetry, :handle_event, [:killmail, :processing]}
  ]

# Configure SSL and security for production
config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  # Force SSL in production if HTTPS is enabled
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    host: nil,
    hsts: true
  ],
  # Security headers
  extra_headers: [
    {"X-Frame-Options", "DENY"},
    {"X-Content-Type-Options", "nosniff"},
    {"X-XSS-Protection", "1; mode=block"},
    {"Strict-Transport-Security", "max-age=31536000; includeSubDomains"},
    {"Content-Security-Policy", "default-src 'self'"}
  ]

# Configure API token at compile time to prevent runtime override
config :wanderer_notifier,
  api_token: System.get_env("NOTIFIER_API_TOKEN") || "missing_token"

# Production performance tuning
config :wanderer_notifier,
  # HTTP client pool configuration
  http_pool_size: 50,
  http_pool_max_overflow: 100,
  http_timeout: 30_000,

  # WebSocket configuration
  websocket_pool_size: 10,
  websocket_reconnect_backoff: [1000, 2000, 5000, 10000],

  # SSE configuration
  sse_pool_size: 5,
  sse_buffer_size: 1000,
  sse_timeout: 60_000,

  # Cache configuration
  cache_cleanup_interval: :timer.hours(1),
  cache_memory_threshold: 0.8,

  # Notification batching for performance
  notification_batch_size: 10,
  notification_batch_timeout: 1000,

  # Rate limiting
  rate_limit_requests_per_minute: 60,
  rate_limit_burst_size: 10

# Disable development-only features in production
config :wanderer_notifier,
  enable_debugging: false,
  enable_profiling: false,
  enable_test_endpoints: false

# Runtime configuration should be in runtime.exs
