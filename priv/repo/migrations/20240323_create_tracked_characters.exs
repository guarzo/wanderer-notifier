defmodule WandererNotifier.Repo.Migrations.CreateTrackedCharacters do
  use Ecto.Migration

  def change do
    create table(:tracked_characters, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :character_id, :integer, null: false
      add :character_name, :string, null: false
      add :corporation_id, :integer
      add :corporation_name, :string
      add :alliance_id, :integer
      add :alliance_name, :string
      add :tracked_since, :utc_datetime_usec, null: false

      timestamps()
    end

    # Add a unique index on character_id
    create unique_index(:tracked_characters, [:character_id], name: :tracked_characters_character_id_index)
  end
end
