defmodule WandererNotifier.Repo.Migrations.TrackingHistory do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    create table(:kill_tracking_history, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:character_id, :bigint, null: false)
      add(:timestamp, :utc_datetime, null: false)
      add(:our_kills_count, :bigint, null: false)
      add(:zkill_kills_count, :bigint, null: false)
      add(:missing_kills, {:array, :bigint})
      add(:analysis_results, :map)
      add(:api_metrics, :map)
      add(:time_range_type, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end
  end

  def down do
    drop(table(:kill_tracking_history))
  end
end
