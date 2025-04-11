defmodule WandererNotifier.Resources.KillmailCharacterInvolvement do
  @moduledoc """
  Ash resource representing the relationship between a tracked character and a killmail.
  This model resolves the many-to-many relationship between characters and killmails,
  storing the role and character-specific data for each involvement.
  """
  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshPostgres.Resource
    ]

  # Predefine atoms to ensure they exist at compile time
  @character_roles [:attacker, :victim]

  postgres do
    table("killmail_character_involvements")
    repo(WandererNotifier.Data.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:character_role, :atom, constraints: [one_of: @character_roles])

    # Store character_id directly as an attribute instead of a relationship
    # This fixes type mismatches with TrackedCharacter which uses integer IDs
    attribute(:character_id, :integer, allow_nil?: false)

    # Character-specific data
    attribute(:ship_type_id, :integer)
    attribute(:ship_type_name, :string)
    attribute(:damage_done, :integer)
    attribute(:is_final_blow, :boolean, default: false)
    attribute(:weapon_type_id, :integer)
    attribute(:weapon_type_name, :string)

    timestamps()
  end

  relationships do
    belongs_to(:killmail, WandererNotifier.Resources.Killmail)

    # Define a manual belongs_to relationship that doesn't create a foreign key constraint
    # This avoids the type mismatch issue with TrackedCharacter
    # belongs_to(:character, WandererNotifier.Resources.TrackedCharacter,
    #   source_attribute: :character_id,
    #   destination_attribute: :character_id,
    #   define_attribute?: false,
    #   primary_key?: false,
    #   foreign_key_constraint?: false
    # )
  end

  identities do
    identity(:unique_involvement, [:killmail_id, :character_id, :character_role])
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)

      accept([
        :character_role,
        :character_id,
        :ship_type_id,
        :ship_type_name,
        :damage_done,
        :is_final_blow,
        :weapon_type_id,
        :weapon_type_name
      ])

      argument(:killmail_id, :string, allow_nil?: false)

      change(fn changeset, _ ->
        killmail_id = Ash.Changeset.get_argument(changeset, :killmail_id)

        changeset
        |> Ash.Changeset.change_attribute(:killmail_id, killmail_id)
      end)

      # Set the timestamps
      change(fn changeset, _context ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        changeset
        |> Ash.Changeset.force_change_attribute(:inserted_at, now)
        |> Ash.Changeset.force_change_attribute(:updated_at, now)
      end)
    end

    read :exists_for_character do
      argument(:killmail_id, :string, allow_nil?: false)
      argument(:character_id, :integer, allow_nil?: false)
      argument(:character_role, :atom, allow_nil?: false)

      filter(
        expr(
          killmail_id == ^arg(:killmail_id) and
            character_id == ^arg(:character_id) and
            character_role == ^arg(:character_role)
        )
      )

      # Just check for existence
      prepare(fn query, _context ->
        query
        |> Ash.Query.select([:id])
        |> Ash.Query.limit(1)
      end)
    end

    read :list_for_character do
      argument(:character_id, :integer, allow_nil?: false)
      argument(:from_date, :utc_datetime_usec, allow_nil?: false)
      argument(:to_date, :utc_datetime_usec, allow_nil?: false)
      argument(:limit, :integer, default: 10)

      filter(expr(character_id == ^arg(:character_id)))

      prepare(fn query, _context ->
        query
        |> Ash.Query.load([:killmail])
        |> Ash.Query.filter(expr(killmail.kill_time >= ^arg(:from_date)))
        |> Ash.Query.filter(expr(killmail.kill_time <= ^arg(:to_date)))
        |> Ash.Query.sort(expr(killmail.kill_time), :desc)
        |> Ash.Query.limit(arg(:limit))
      end)
    end
  end

  code_interface do
    define(:get, action: :read)
    define(:create, action: :create)
    define(:update, action: :update)
    define(:destroy, action: :destroy)

    define(:exists_for_character,
      action: :exists_for_character,
      args: [:killmail_id, :character_id, :character_role]
    )

    define(:list_for_character,
      action: :list_for_character,
      args: [:character_id, :from_date, :to_date, :limit]
    )
  end
end
