# Exsync Hot Reloading Guide

## Starting the Application with Exsync

1. **The MIX_ENV should be lowercase `dev`**, not `DEV`:
   ```bash
   export MIX_ENV=dev  # or just omit it, as dev is the default
   ```

2. **Start the application**:
   ```bash
   iex -S mix
   # or
   ./start_with_exsync.sh
   ```

3. **Verify exsync is running** - You should see in the startup logs:
   - Look for file_system starting
   - No specific "exsync started" message, but it's running if no errors

## Testing Hot Reload

1. In your iex session, test the module:
   ```elixir
   iex> TestHotReload.hello()
   "Hello from hot reload! Change this message and save to test."
   ```

2. Edit `/workspace/lib/test_hot_reload.ex` and change the message

3. Save the file - you should see:
   ```
   Recompiled Elixir.TestHotReload
   ```

4. Call the function again to see your changes:
   ```elixir
   iex> TestHotReload.hello()
   "Your new message here!"
   ```

## Troubleshooting

If hot reloading isn't working:

1. **Check MIX_ENV**:
   ```bash
   echo $MIX_ENV  # Should be empty or "dev" (lowercase)
   ```

2. **Verify file_system is running**:
   ```elixir
   iex> Application.started_applications() |> Enum.find(fn {app, _, _} -> app == :file_system end)
   # Should return {:file_system, 'Native file system event monitor', '1.1.0'} or similar
   ```

3. **Check exsync configuration**:
   ```elixir
   iex> Application.get_all_env(:exsync)
   # Should show [reload_timeout: 150, extensions: [".ex", ".exs"]]
   ```

4. **Manual reload** (if automatic isn't working):
   ```elixir
   iex> IEx.Helpers.recompile()
   ```

## Notes

- Exsync only works in `:dev` environment
- It watches `.ex` and `.exs` files (configured in config/dev.exs)
- Changes to `.eex` templates or other files won't trigger reload
- Some changes (like adding new dependencies) require restarting iex