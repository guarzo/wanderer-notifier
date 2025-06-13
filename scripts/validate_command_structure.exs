#!/usr/bin/env elixir

# Validate the command structure
IO.puts("🔍 Validating Command Structure...")
IO.puts("==================================\n")

commands = WandererNotifier.Discord.CommandRegistrar.commands()

Enum.each(commands, fn cmd ->
  IO.puts("Command: #{cmd.name}")
  IO.puts("  Type: #{cmd.type} (should be 1 for CHAT_INPUT)")
  IO.puts("  Description: #{cmd.description} (length: #{String.length(cmd.description)})")
  
  if String.length(cmd.description) > 100 do
    IO.puts("  ⚠️  Description too long! Max 100 chars")
  end
  
  if cmd.options do
    IO.puts("  Options (#{length(cmd.options)}):")
    Enum.each(cmd.options, fn opt ->
      IO.puts("    - #{opt.name} (type: #{opt.type})")
      IO.puts("      Description: #{opt.description}")
      
      if opt[:options] do
        IO.puts("      Sub-options:")
        Enum.each(opt.options, fn sub ->
          IO.puts("        * #{sub.name} (type: #{sub.type}, required: #{sub.required})")
          if sub[:choices] do
            IO.puts("          Choices: #{Enum.map(sub.choices, & &1.name) |> Enum.join(", ")}")
          end
        end)
      end
    end)
  end
  
  IO.puts("")
end)

IO.puts("\n📝 Command Type Reference:")
IO.puts("1 = CHAT_INPUT (slash commands)")
IO.puts("2 = USER (user context menu)")
IO.puts("3 = MESSAGE (message context menu)")
IO.puts("\n📝 Option Type Reference:")
IO.puts("1 = SUB_COMMAND")
IO.puts("2 = SUB_COMMAND_GROUP")
IO.puts("3 = STRING")
IO.puts("4 = INTEGER")
IO.puts("5 = BOOLEAN")
IO.puts("6 = USER")
IO.puts("7 = CHANNEL")
IO.puts("8 = ROLE")