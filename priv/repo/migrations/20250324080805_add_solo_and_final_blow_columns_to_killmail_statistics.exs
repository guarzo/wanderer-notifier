defmodule WandererNotifier.Repo.Migrations.AddSoloAndFinalBlowColumnsToKillmailStatistics do
  use Ecto.Migration

  def change do
    alter table(:killmail_statistics) do
      add :solo_kills_count, :integer, default: 0, null: false
      add :final_blows_count, :integer, default: 0, null: false
    end
  end
end
