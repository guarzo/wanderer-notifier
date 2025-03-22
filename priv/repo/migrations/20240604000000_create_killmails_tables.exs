defmodule WandererNotifier.Repo.Migrations.CreateKillmailsTables do
  use Ecto.Migration

  def change do
    create table(:killmails, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :killmail_id, :bigint, null: false
      add :kill_time, :utc_datetime_usec
      add :solar_system_id, :integer
      add :solar_system_name, :string
      add :region_id, :integer
      add :region_name, :string
      add :total_value, :decimal, precision: 20, scale: 2

      add :character_role, :string, null: false
      add :related_character_id, :integer, null: false
      add :related_character_name, :string

      add :ship_type_id, :integer
      add :ship_type_name, :string

      add :zkb_data, :map
      add :victim_data, :map
      add :attacker_data, :map

      add :processed_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:killmails, [:killmail_id])
    create index(:killmails, [:related_character_id, :kill_time])
    create index(:killmails, [:solar_system_id, :kill_time])
    create index(:killmails, [:character_role, :kill_time])

    create table(:killmail_statistics, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :period_type, :string, null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false

      add :character_id, :integer, null: false
      add :character_name, :string

      add :kills_count, :integer, default: 0
      add :deaths_count, :integer, default: 0
      add :isk_destroyed, :decimal, precision: 20, scale: 2, default: 0
      add :isk_lost, :decimal, precision: 20, scale: 2, default: 0

      add :region_activity, :map
      add :ship_usage, :map
      add :top_victim_corps, :map
      add :top_victim_ships, :map
      add :detailed_ship_usage, :map

      timestamps()
    end

    create unique_index(:killmail_statistics, [:character_id, :period_type, :period_start])
  end
end
