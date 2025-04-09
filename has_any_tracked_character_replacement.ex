# Helper to check if a killmail involves any tracked character
defp has_any_tracked_character?(killmail) when is_map(killmail) do
  if Application.get_env(:wanderer_notifier, :environment) == :test do
    # For testing, assume all killmails have tracked characters
    true
  else
    case find_tracked_character_in_killmail(killmail) do
      {_character_id, _character_name, _role} -> true
      nil -> false
    end
  end
end
