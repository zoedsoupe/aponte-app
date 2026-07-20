defmodule Aponte.Repo.Migrations.RebuildMerchAndCouponsOrgIdNotNull do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Three rebuilds in one pinned connection. FKs off: merch_items is
    # referenced by order_items, merch_units, bar_sale_items and
    # edition_merch_items; coupons references coupon_rules (rebuilt first so
    # coupons_new points at the renamed table).
    repo().checkout(fn ->
      repo().query!("PRAGMA foreign_keys=OFF")

      repo().query!("""
      CREATE TABLE merch_items_new (
        id TEXT PRIMARY KEY,
        org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT,
        name TEXT NOT NULL,
        description TEXT,
        price_cents INTEGER NOT NULL,
        stock INTEGER NOT NULL,
        available INTEGER NOT NULL,
        image_path TEXT,
        is_active INTEGER NOT NULL DEFAULT true,
        position INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'online',
        track_stock INTEGER NOT NULL DEFAULT true,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO merch_items_new
        (id, org_id, name, description, price_cents, stock, available,
         image_path, is_active, position, kind, track_stock,
         inserted_at, updated_at)
      SELECT
         id, org_id, name, description, price_cents, stock, available,
         image_path, is_active, position, kind, track_stock,
         inserted_at, updated_at
      FROM merch_items
      """)

      repo().query!("DROP TABLE merch_items")
      repo().query!("ALTER TABLE merch_items_new RENAME TO merch_items")

      repo().query!(
        "CREATE INDEX merch_items_is_active_position_index ON merch_items (is_active, position)"
      )

      repo().query!("CREATE INDEX merch_items_org_id_index ON merch_items (org_id)")

      repo().query!("""
      CREATE TABLE coupon_rules_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT,
        name TEXT NOT NULL,
        min_order_cents INTEGER NOT NULL,
        discount_kind TEXT NOT NULL,
        discount_value INTEGER NOT NULL,
        expires_in_days INTEGER NOT NULL DEFAULT 7,
        is_active INTEGER NOT NULL DEFAULT true,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO coupon_rules_new
        (id, org_id, name, min_order_cents, discount_kind, discount_value,
         expires_in_days, is_active, inserted_at, updated_at)
      SELECT
         id, org_id, name, min_order_cents, discount_kind, discount_value,
         expires_in_days, is_active, inserted_at, updated_at
      FROM coupon_rules
      """)

      repo().query!("DROP TABLE coupon_rules")
      repo().query!("ALTER TABLE coupon_rules_new RENAME TO coupon_rules")
      repo().query!("CREATE INDEX coupon_rules_org_id_index ON coupon_rules (org_id)")

      repo().query!("""
      CREATE TABLE coupons_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        scope TEXT NOT NULL,
        discount_kind TEXT NOT NULL,
        discount_value INTEGER NOT NULL,
        expires_at TEXT,
        min_order_cents INTEGER,
        is_active INTEGER NOT NULL DEFAULT true,
        rule_id INTEGER REFERENCES coupon_rules(id) ON DELETE SET NULL,
        customer_instagram TEXT,
        client_endpoint TEXT,
        order_id TEXT,
        used_at TEXT,
        used_order_id TEXT,
        notified_expiring_at TEXT,
        max_uses INTEGER,
        uses_count INTEGER NOT NULL DEFAULT 0,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

      repo().query!("""
      INSERT INTO coupons_new
        (id, org_id, code, scope, discount_kind, discount_value, expires_at,
         min_order_cents, is_active, rule_id, customer_instagram,
         client_endpoint, order_id, used_at, used_order_id,
         notified_expiring_at, max_uses, uses_count, inserted_at, updated_at)
      SELECT
         id, org_id, code, scope, discount_kind, discount_value, expires_at,
         min_order_cents, is_active, rule_id, customer_instagram,
         client_endpoint, order_id, used_at, used_order_id,
         notified_expiring_at, max_uses, uses_count, inserted_at, updated_at
      FROM coupons
      """)

      repo().query!("DROP TABLE coupons")
      repo().query!("ALTER TABLE coupons_new RENAME TO coupons")
      # Codes stay globally unique; redemption is org-scoped at the app layer.
      repo().query!("CREATE UNIQUE INDEX coupons_code_index ON coupons (code)")
      repo().query!("CREATE INDEX coupons_scope_index ON coupons (scope)")
      repo().query!("CREATE INDEX coupons_org_id_index ON coupons (org_id)")
      repo().query!("PRAGMA foreign_key_check")
      repo().query!("PRAGMA foreign_keys=ON")
    end)
  end

  def down, do: raise("irreversible: merch_items/coupons/coupon_rules org_id NOT NULL")
end
