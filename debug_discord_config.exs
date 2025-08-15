#!/usr/bin/env elixir

# Diagnostic script for Discord configuration issues
# Run with: elixir debug_discord_config.exs

IO.puts("\n=== Discord Configuration Diagnostic ===\n")

# Check environment variable directly
env_value = System.get_env("DISCORD_APPLICATION_ID")
IO.puts("1. Environment variable DISCORD_APPLICATION_ID:")
IO.puts("   Raw value: #{inspect(env_value)}")
IO.puts("   Is nil? #{env_value == nil}")
IO.puts("   Is empty? #{env_value == ""}")
IO.puts("   Length: #{if env_value, do: String.length(env_value), else: "N/A"}")

# Check for hidden characters
if env_value do
  IO.puts("\n2. Character analysis:")
  IO.puts("   Bytes: #{inspect(:erlang.binary_to_list(env_value))}")
  IO.puts("   Contains whitespace? #{env_value != String.trim(env_value)}")
  IO.puts("   Trimmed value: #{inspect(String.trim(env_value))}")
  
  # Try parsing as integer
  IO.puts("\n3. Integer parsing:")
  case Integer.parse(env_value) do
    {int_val, remainder} ->
      IO.puts("   Parsed integer: #{int_val}")
      IO.puts("   Remainder: #{inspect(remainder)}")
      IO.puts("   Valid? #{remainder == ""}")
    :error ->
      IO.puts("   ERROR: Cannot parse as integer")
  end
end

# Check all Discord-related env vars
IO.puts("\n4. All Discord environment variables:")
discord_vars = [
  "DISCORD_APPLICATION_ID",
  "DISCORD_BOT_TOKEN",
  "DISCORD_CHANNEL_ID",
  "DISCORD_GUILD_ID"
]

for var <- discord_vars do
  val = System.get_env(var)
  if val do
    IO.puts("   #{var}: SET (length: #{String.length(val)})")
  else
    IO.puts("   #{var}: NOT SET")
  end
end

# Check .env file if it exists
IO.puts("\n5. Checking .env file:")
case File.read(".env") do
  {:ok, content} ->
    lines = String.split(content, "\n")
    discord_lines = Enum.filter(lines, &String.contains?(&1, "DISCORD_APPLICATION_ID"))
    
    if Enum.empty?(discord_lines) do
      IO.puts("   DISCORD_APPLICATION_ID not found in .env file")
    else
      IO.puts("   Found in .env file:")
      for line <- discord_lines do
        IO.puts("   #{inspect(line)}")
      end
    end
  {:error, _} ->
    IO.puts("   No .env file found")
end

# Check common issues
IO.puts("\n6. Common issues check:")

if env_value do
  # Check for quotes
  if String.starts_with?(env_value, "\"") or String.ends_with?(env_value, "\"") do
    IO.puts("   ⚠️  WARNING: Value contains quotes - should be unquoted")
  end
  
  # Check for common prefixes
  if String.contains?(env_value, "Bot ") do
    IO.puts("   ⚠️  WARNING: Value contains 'Bot ' prefix - should be just the ID")
  end
  
  # Check length (Discord app IDs are typically 18-19 digits)
  if String.length(env_value) < 17 or String.length(env_value) > 20 do
    IO.puts("   ⚠️  WARNING: Unusual length for Discord app ID (expected 18-19 digits)")
  end
  
  # Check if all characters are digits
  if Regex.match?(~r/^\d+$/, env_value) do
    IO.puts("   ✓ Value contains only digits")
  else
    IO.puts("   ⚠️  WARNING: Value contains non-digit characters")
  end
end

IO.puts("\n=== End of diagnostic ===\n")