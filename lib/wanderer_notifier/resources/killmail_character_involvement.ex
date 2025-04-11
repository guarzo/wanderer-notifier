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

    attribute(:character_id, :integer, allow_nil?: false)

    # Use integer killmail_id to match the external identifier from EVE Online
    attribute(:killmail_id, :integer, allow_nil?: false)

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
    # Define the relationship using the numeric killmail_id, not the UUID
    belongs_to(:killmail, WandererNotifier.Resources.Killmail,
      source_attribute: :killmail_id,
      destination_attribute: :killmail_id,
      primary_key?: false,
      define_attribute?: false
    )
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

      argument(:killmail_id, :integer, allow_nil?: false)

      change(fn changeset, _ ->
        killmail_id = Ash.Changeset.get_argument(changeset, :killmail_id)

        # Convert killmail_id to integer if it's a string
        killmail_id_int =
          case killmail_id do
            x when is_integer(x) ->
              x

            x when is_binary(x) ->
              case Integer.parse(x) do
                {int, _} -> int
                :error -> raise "Invalid killmail_id: #{inspect(x)}"
              end

            nil ->
              raise "killmail_id cannot be nil"

            _ ->
              raise "Invalid killmail_id type: #{inspect(killmail_id)}"
          end

        changeset
        |> Ash.Changeset.change_attribute(:killmail_id, killmail_id_int)
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
      argument(:killmail_id, :integer, allow_nil?: false)
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
