defmodule Aponte.Repo.Migrations.RebuildEditionsOrgIdNotNull do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Same rebuild pattern as MakeOrdersEditionNullable: one pinned connection,
    # no transaction, FKs off so the DROP doesn't cascade into ticket_types,
    # orders, tickets, bar_sales, edition_merch_items or merch_units.
    repo().checkout(fn ->
      repo().query!("PRAGMA foreign_keys=OFF")

      repo().query!("""
      CREATE TABLE editions_new (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT,
        number INTEGER NOT NULL,
        name TEXT NOT NULL,
        starts_at TEXT NOT NULL,
        ends_at TEXT,
        venue TEXT NOT NULL,
        venue_address TEXT,
        lineup TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        accent_color TEXT NOT NULL DEFAULT '#F07BC0',
        logo_path TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO editions_new
        (id, org_id, number, name, starts_at, venue, venue_address, lineup,
         status, accent_color, logo_path, inserted_at, updated_at)
      SELECT
         id, org_id, number, name, starts_at, venue, venue_address, lineup,
         status, accent_color, logo_path, inserted_at, updated_at
      FROM editions
      """)

      repo().query!("DROP TABLE editions")
      repo().query!("ALTER TABLE editions_new RENAME TO editions")
      # Edition numbers are per-org now.
      repo().query!(
        "CREATE UNIQUE INDEX editions_org_id_number_index ON editions (org_id, number)"
      )

      repo().query!("CREATE INDEX editions_status_index ON editions (status)")
      repo().query!("CREATE INDEX editions_org_id_index ON editions (org_id)")
      repo().query!("PRAGMA foreign_key_check")
      repo().query!("PRAGMA foreign_keys=ON")
    end)
  end

  def down, do: raise("irreversible: editions.org_id NOT NULL + ends_at")
end
