defmodule Aponte.Repo.Migrations.RebuildOrdersOrgAndPhone do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Rebuild pattern: FKs off so the DROP doesn't cascade into order_items,
    # tickets or merch_units. Folds in three changes at once: org_id NOT NULL,
    # customer_phone (new), customer_instagram now nullable (buyer identity is
    # "instagram OR phone" from here on).
    repo().checkout(fn ->
      repo().query!("PRAGMA foreign_keys=OFF")

      repo().query!("""
      CREATE TABLE orders_new (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT,
        edition_id TEXT REFERENCES editions(id) ON DELETE RESTRICT,
        status TEXT NOT NULL DEFAULT 'pending',
        customer_name TEXT NOT NULL,
        customer_instagram TEXT,
        customer_phone TEXT,
        total_cents INTEGER NOT NULL,
        coupon_code TEXT,
        discount_cents INTEGER NOT NULL DEFAULT 0,
        pix_key TEXT,
        client_endpoint TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO orders_new
        (id, org_id, edition_id, status, customer_name, customer_instagram,
         total_cents, coupon_code, discount_cents, pix_key, client_endpoint,
         inserted_at, updated_at)
      SELECT
         id, org_id, edition_id, status, customer_name, customer_instagram,
         total_cents, coupon_code, discount_cents, pix_key, client_endpoint,
         inserted_at, updated_at
      FROM orders
      """)

      repo().query!("DROP TABLE orders")
      repo().query!("ALTER TABLE orders_new RENAME TO orders")
      repo().query!("CREATE INDEX orders_status_index ON orders (status)")
      repo().query!("CREATE INDEX orders_edition_id_index ON orders (edition_id)")
      repo().query!("CREATE INDEX orders_org_id_index ON orders (org_id)")
      repo().query!("PRAGMA foreign_key_check")
      repo().query!("PRAGMA foreign_keys=ON")
    end)
  end

  def down, do: raise("irreversible: orders.org_id NOT NULL + customer_phone")
end
