Here’s how you might do it in Elixir with Nostrum to collect members across multiple voice channels (excluding AFK), build individual mentions, and post them to a text channel:

elixir
Copy
Edit
defmodule MyBot.KillNotifier do
@moduledoc """
On an Eve kill event, pings only users currently in voice channels.
"""

alias Nostrum.Api
alias Nostrum.Cache.GuildCache
alias Nostrum.Cache.GuildChannelCache
alias Nostrum.Struct.{Guild, Channel, VoiceState}

@guild_id 123_456_789012345678 # your guild/server ID
@text_channel_id 234_567_890123456789 # channel to post kill alerts

@doc """
Call this when a kill is detected. It will: 1. Load all voice channels in the guild (excluding the AFK channel). 2. Gather all connected non-bot members. 3. Send a message tagging each one individually.
"""
def handle_kill_event(\_kill_payload) do
guild = GuildCache.get!(@guild_id)

    # 1️⃣ Find all voice-channel IDs except the AFK channel
    voice_channel_ids =
      GuildChannelCache.get_all(@guild_id)
      |> Enum.filter(&voice_channel?/1)
      |> Enum.reject(&(&1.id == guild.afk_channel_id))
      |> Enum.map(& &1.id)

    # 2️⃣ Gather all voice states for those channels
    mentions =
      guild.voice_states
      |> Map.values()
      |> Enum.filter(fn %VoiceState{channel_id: cid, user_id: uid} ->
        cid in voice_channel_ids and                       # in a target VC
          not user_is_bot?(uid)                             # skip bots
      end)
      |> Enum.map(&"&lt;@#{&1.user_id}&gt;")
      |> Enum.uniq()

    # 3️⃣ Send the message
    message =
      case mentions do
        [] -> "⚠️ Kill detected, but no one is in voice channels."
        ms -> "⚠️ Kill detected! #{Enum.join(ms, " ")}"
      end

    Api.create_message(@text_channel_id, message)

end

# Helpers

defp voice*channel?(%Channel{type: :voice}), do: true
defp voice_channel?(*), do: false

defp user*is_bot?(user_id) do
case Api.get_user(user_id) do
{:ok, %{"bot" => true}} -> true
* -> false
end
end
end
AI Prompt to Convert Your Existing Implementation
Use this prompt with any LLM-assisted refactoring tool (like Copilot, ChatGPT, etc.) to transform your current “@here”-based code into the above dynamic-mentions approach:

sql
Copy
Edit
You are an Elixir developer assistant. I have existing code that calls
Api.create_message(channel_id, "@here A kill was scored!")
to notify everyone. I want to refactor it so that instead of @here,
it:

1. Fetches all voice channels in the guild except the AFK channel.
2. Gathers only the non-bot users currently in those voice channels.
3. Sends a message tagging each user individually.

Please:
• Rewrite the notification function to use Nostrum.Cache.GuildCache
and Nostrum.Cache.GuildChannelCache to collect voice channels.
• Use the guild’s `voice_states` map to list connected users.
• Build mentions like `<@user_id>`, dedupe them, and send a single
message.
• Maintain config via module attributes for guild_id and text_channel_id.
• Provide the complete refactored function with necessary helpers.

Here’s my current version (Elixir/Nostrum):

```elixir
def handle_kill_event(_kill_payload) do
  Api.create_message(channel_id, "@here Kill detected!")
end
pgsql
Copy
Edit

That prompt gives the LLM the full “before” context and clear “after” requirements, ensuring you walk away with working Elixir/Nostrum code that pings only active voice participants.
```
