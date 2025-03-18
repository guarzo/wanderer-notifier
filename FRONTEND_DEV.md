# Frontend Development Guide

This guide explains how the automatic asset building system works in this project and how to use it effectively during development.

## Automatic Asset Building

The React assets in this project are automatically built during development through a well-orchestrated system:

1. **Phoenix Watchers**: In `config/dev.exs`, Phoenix is configured with a watcher that automatically runs the "watch" script from the renderer directory:

   ```elixir
   config :wanderer_notifier,
     watchers: [
       npm: ["run", "watch", cd: Path.expand("../renderer", __DIR__)]
     ]
   ```

2. **Vite Watch Mode**: In `renderer/package.json`, the "watch" script is defined as:

   ```json
   "watch": "vite build --watch --minify false --emptyOutDir false --mode development"
   ```

   This uses Vite in watch mode to continuously rebuild assets whenever files change. The key flags are:
   - `--watch`: Tells Vite to watch for file changes
   - `--minify false`: Skips minification for faster builds in development
   - `--emptyOutDir false`: Preserves existing files in the output directory
   - `--mode development`: Uses development-specific settings

3. **Startup Process**: When you run `mix phx.server` or `iex -S mix phx.server` (or the shortcut `make dev` or `make dev.s`), Phoenix automatically starts this watcher, which in turn runs Vite in watch mode.

## Development Commands

The following commands are available for development:

- `make dev`: Start the Phoenix server with automatic asset rebuilding
- `make dev.s`: Clean, compile, and start the Phoenix server with automatic asset rebuilding
- `make watch`: Manually run the Vite watch script (for standalone frontend development)
- `make build.npm`: Build the frontend assets once (for production or testing)

## How It Works

When the application starts in development mode, the following happens:

1. The application checks for development mode and starts the asset watchers
2. The watchers run the `npm run watch` command in the `renderer` directory
3. Vite watches for file changes and automatically rebuilds the assets
4. The rebuilt assets are placed in the `renderer/dist` directory
5. The assets are then copied to the Phoenix static directory where they can be served

## Customizing the Setup

If you need to customize the asset building process:

1. Edit the `watch` script in `renderer/package.json` to change Vite's options
2. Edit the watcher configuration in `config/dev.exs` to change how Phoenix starts the watchers
3. Modify the `start_watchers` function in `lib/wanderer_notifier/application.ex` for more advanced control

## Troubleshooting

- **Assets not updating**: Make sure the watcher is running. Check the console output for any errors.
- **Slow builds**: Consider reducing the scope of what Vite watches or adjust the build options.
- **Watcher crashes**: Check the logs for error messages. You might need to install missing npm packages. 