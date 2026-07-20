defmodule Aponte.Repo.Migrations.RebuildTicketsOrgIdNotNull do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Nothing references tickets, but FK-off keeps the pattern uniform.
    repo().checkout(fn ->
      repo().query!("PRAGMA foreign_keys=OFF")

      repo().query!("""
      CREATE TABLE tickets_new (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT,
        order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        ticket_type_id TEXT NOT NULL REFERENCES ticket_types(id) ON DELETE RESTRICT,
        edition_id TEXT NOT NULL REFERENCES editions(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        used_at TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO tickets_new
        (id, org_id, order_id, ticket_type_id, edition_id, code, used_at,
         inserted_at, updated_at)
      SELECT
         id, org_id, order_id, ticket_type_id, edition_id, code, used_at,
         inserted_at, updated_at
      FROM tickets
      """)

      repo().query!("DROP TABLE tickets")
      repo().query!("ALTER TABLE tickets_new RENAME TO tickets")
      # Code stays globally unique (door validation is a single-table lookup).
      repo().query!("CREATE UNIQUE INDEX tickets_code_index ON tickets (code)")
      repo().query!("CREATE INDEX tickets_edition_id_index ON tickets (edition_id)")
      repo().query!("CREATE INDEX tickets_order_id_index ON tickets (order_id)")
      repo().query!("CREATE INDEX tickets_org_id_index ON tickets (org_id)")
      repo().query!("PRAGMA foreign_key_check")
      repo().query!("PRAGMA foreign_keys=ON")
    end)
  end

  def down, do: raise("irreversible: tickets.org_id NOT NULL")
end
