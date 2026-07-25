# SPEC: sesh_lab -> Aponte (multi-org event PWA)

Status: design aprovado para implementacao (2026-07-19). Escopo de produto em
`SPEC_APONTE.md`. Gerada pelo elixir-systems-designer a partir de leitura
completa do app (mix.exs, application.ex, router, contexts, schemas, 14
migrations, plugs, configs, fly.toml, admin LiveViews, JS cliente, layouts).

## 1. Design summary

sesh_lab becomes Aponte **in place**: same Fly app, same `sesh_data` volume, same SQLite file, no dump/import. An `orgs` table becomes the tenant root. Editions belong directly to an org; orders, tickets, merch, coupons, and coupon rules get denormalized `org_id` (NOT NULL after backfill); push subscriptions and DJ applications get nullable `org_id`; bar sales derive org through their edition (no new column). Every context query that today is global gains an org scope parameter. Public URLs become `/:org_slug/...` behind an org-loader plug; `/` becomes the Aponte home. Admin moves under `/admin/:org_slug/...` behind the same loader (still single basic auth, isolated so session auth + org_memberships can replace it later). Buyer identity relaxes to "instagram OR phone" at the changeset boundary; `meus-ingressos` gains a rate-limited phone+code lookup. Pix key moves from env to `orgs.pix_key` (orders keep snapshotting it). A per-org gallery (`org_images` on disk, libvips via `image`, soft quota) powers the vitrine.

**Trade-offs decided (and why):**

1. **SQLite table rebuilds for NOT NULL `org_id`, not app-layer-only enforcement.** SQLite cannot `ALTER COLUMN ... SET NOT NULL`, but the repo already has the proven rebuild pattern (`20260626000001_make_orders_edition_nullable.exs`: `repo().checkout` + `PRAGMA foreign_keys=OFF` + copy/rename). Product asked for "not null after backfill"; the pattern exists and the DB is ~150 orders. We rebuild 6 tables once and get real FK + NOT NULL guarantees. The same rebuilds let us fold in `editions.ends_at`, `orders.customer_phone`, and relaxing `orders.customer_instagram` to nullable **for free** (no extra rebuilds).
2. **No Oban, no Hammer, no storage behaviour.** Image processing runs in-request inside the LiveView upload consume (vips handles a 5 MB image in well under a second; admin uploads a few at a time). Rate limiting reuses the existing ETS-based `Plugs.RateLimit` (no dep). Storage is local disk with a tmp-dir root in test config; the only `@behaviour` added is `Aponte.Images.Processor` (libvips impl + Fake), because the native dep is the real test boundary, not the filesystem.
3. **Rename ships before orgs.** The `SeshLab -> Aponte` rename is mechanical and touches every file; doing it first keeps the org-refactor diff reviewable and each deploy bootable. DB is untouched by the rename (schema_migrations stores versions, not module names).
4. **Bar sales get no `org_id` column.** `bar_sales.edition_id` exists (nullable). Org comes through the edition; a null-edition sale in a single-operator v1 is acceptable. Adding a denormalized column to a table whose sales are recorded by the same admin who picked the org buys nothing.
5. **Coupon codes stay globally unique; redemption is org-scoped.** `get_by_code` becomes org-scoped so org A cannot redeem org B's public coupon, but the unique index on `code` stays global (codes are random, collision handling already exists).

## 2. Open questions / assumptions

These do **not** block the build; defaults are stated and the implementer should use them unless corrected:

- **Aponte default accent** (used on `/`, `/sobre`, and any org-less page): `#BF7262` (terracotta, from the palm of the watercolor logo). The `sesh` org keeps `#F07BC0`. Full palette decided 2026-07-20 — see section 2.1.
- **Default storage quota**: `52_428_800` bytes (50 MiB). At ~300 KB per 1600px webp + ~40 KB thumb that is ~150 images, far above the "10 images worth" floor; quota is soft-enforced anyway.
- **"Order code" for meus-ingressos lookup = the full order UUID** (the code buyers already have in their `/compra/:id` link). No new short code is minted. Lookup without a matching phone reveals nothing.
- **Bound coupons require instagram.** `Coupon.bound_changeset` validates `customer_instagram` required and redemption matches on handle. Phone-only orders earn no bound coupons (`Coupons.issue_for_order/1` becomes a no-op when `customer_instagram` is nil). Public coupons still work for phone-only buyers. Flagged here because it is a product-visible consequence of making instagram optional.
- **`dj_applications_open` flag (Settings KV) stays global**, not per-org. Trigger to make it per-org: a second org that wants its own tocar schedule.
- **`MERCHANT_NAME` env is retired**; Pix `merchant_name` becomes the org name (sanitized by `Pix.build` already). `MERCHANT_CITY` env stays as the global default city.
- **Domain `aponte.live` is not purchased yet.** All config uses it as a placeholder behind env (`PHX_HOST`); nothing hard-codes it outside config and the legacy-redirect plug's target host, which is also config-driven.
- **DNS/SEO**: old global paths (`/comprar`, `/loja`, etc.) on the NEW domain 301 to the `sesh` slug equivalents for a transition window (see router diff).

### 2.1 Aponte brand palette

Extracted from the watercolor hand logo (`aponte-logo.png`, pointing finger — the "aponte"/point gesture) via histogram + region sampling, approved 2026-07-20. These are the **Aponte platform defaults** (org-less pages + base app theme); org accents override only the accent var.

| Token | Hex | Source region | Use |
|---|---|---|---|
| `--bg` | `#FEF8DA` | paper background | app background |
| `--surface` | `#F3EBC3` | deeper cream | cards, inputs |
| `--ink` | `#49422F` | hand outline | primary text |
| `--ink-muted` | `#91817C` | washed outline | secondary text |
| `--accent` | `#BF7262` | palm terracotta-red | Aponte default accent (CTAs, links) |
| `--accent-warm` | `#DE9B68` | knuckle orange | hover, highlights |
| `--accent-yellow` | `#EDCF63` | pointing finger | badges, callouts |
| `--accent-green` | `#B6C7A8` | thumb sage | success states |
| `--accent-mauve` | `#967577` | wrist | info/subtle accents |

Contrast: `--ink` on `--bg` ≈ 9:1 (AAA). `--accent` on cream ≈ 3.3:1 — fine as CTA fill with cream/white text (AA-large); for small accent-colored text use `--ink` or darken to `#A85A4B`. The logo stays raster (jpg) — watercolor doesn't vectorize cleanly; no SVG needed.

## 3. Migration sequence

All migrations run on boot via the existing `Ecto.Migrator` child (`application.ex`, gated on `RELEASE_NAME`). Ordered list; timestamps `20260719000001..8`. Migrations 4-7 use the exact `repo().checkout` + `PRAGMA foreign_keys=OFF` pattern from `MakeOrdersEditionNullable` (including `PRAGMA foreign_key_check` before re-enabling) and `@disable_ddl_transaction true` / `@disable_migration_lock true`.

**M1 `CreateOrgs`** (plain `change`):
```elixir
create table(:orgs, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :slug, :string, null: false
  add :name, :string, null: false
  add :about, :text
  add :accent_color, :string, null: false, default: "#F07BC0"
  add :logo_path, :string
  add :instagram, :string
  add :pix_key, :string
  add :status, :string, null: false, default: "active"
  add :tier, :string, null: false, default: "free"
  add :storage_quota_bytes, :integer, null: false, default: 52_428_800
  # JSON list of %{"label" => ..., "url" => ...}; simplest for SQLite, no join table.
  add :social_links, {:array, :map}, null: false, default: []
  timestamps()
end
create unique_index(:orgs, [:slug])
```
Then seed the single org inside the migration (`repo().query!` with a `Ecto.UUID.generate()`), slug `"sesh"`, name `"SESH"`, accent `#F07BC0`, pix_key read from `System.get_env("PIX_KEY")` (may be NULL; the follow-up is one `UPDATE orgs SET pix_key = ...` via `fly ssh console` remote if the env was absent at deploy — the deploy that runs these migrations MUST still have `PIX_KEY` set).

**M2 `AddOrgIdColumns`** (plain alters, all nullable):
- `editions`, `orders`, `tickets`, `merch_items`, `coupons`, `coupon_rules`: `add :org_id, references(:orgs, type: :binary_id, on_delete: :restrict)`
- `push_subscriptions`, `dj_applications`: `add :org_id, references(:orgs, type: :binary_id, on_delete: :nilify_all)` (nullable forever by design)
- `create index(...)` on each new column.

**M3 `BackfillOrgIds`** (`up` only, irreversible-down raise): one `UPDATE <table> SET org_id = (SELECT id FROM orgs WHERE slug = 'sesh')` per table from M2. Single org exists, so no joins needed. Orders with `edition_id IS NULL` (pure-merch) included.

**M4 `RebuildEditionsOrgIdNotNull`**: rebuild `editions` with `org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT` **and** new nullable `ends_at TEXT` (utc_datetime, matching `starts_at`). Recreate indexes: `unique_index(:editions, [:number])` becomes `unique_index(:editions, [:org_id, :number])` (numbers are per-org now), plus `(:status)` and `(:org_id)`. FK-off required: `ticket_types`, `orders`, `tickets`, `bar_sales`, `edition_merch_items`, `merch_units` all reference `editions`.

**M5 `RebuildOrdersOrgAndPhone`**: rebuild `orders` with `org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT`, new nullable `customer_phone TEXT`, and `customer_instagram TEXT` now **nullable** (it was NOT NULL). Recreate indexes `(:status)`, `(:edition_id)`, `(:org_id)`. FK-off required: `order_items`, `tickets`, `merch_units` cascade from `orders`.

**M6 `RebuildTicketsOrgIdNotNull`**: rebuild `tickets` adding `org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT`; recreate `unique_index(:tickets, [:code])` (stays global), `(:edition_id)`, `(:order_id)`, `(:org_id)`. Nothing references tickets, FK-off still harmless (keep pattern uniform).

**M7 `RebuildMerchAndCouponsOrgIdNotNull`**: rebuild `merch_items`, `coupons`, `coupon_rules` each with `org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE RESTRICT`. `merch_items` FK-off: referenced by `order_items`, `merch_units`, `bar_sale_items`, `edition_merch_items`. Preserve `unique_index(:coupons, [:code])` global, `index(:coupons, [:scope])`, merch `(:is_active, :position)`.

**M8 `CreateOrgImages`** (plain `change`):
```elixir
create table(:org_images, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
  add :path, :string, null: false              # web variant filename, content-hashed
  add :thumb_path, :string, null: false
  add :original_filename, :string
  add :content_hash, :string, null: false      # sha256 hex of the original upload
  add :position, :integer, null: false, default: 0
  add :byte_size, :integer, null: false        # web + thumb bytes (real disk usage)
  timestamps(updated_at: false)
end
create index(:org_images, [:org_id])
create unique_index(:org_images, [:org_id, :content_hash])  # re-upload dedups
```

Backfill strategy for prod is therefore fully in-migration: edition 1 and ~150 orders get `org_id = sesh` in M3; rebuilds copy rows verbatim. No data loss paths: every rebuild is copy-then-rename with `foreign_key_check` before commit.

## 4. Module / context layout

### Rename map (applies everywhere, mechanical)
`SeshLab` -> `Aponte`, `SeshLabWeb` -> `AponteWeb`, `:sesh_lab` -> `:aponte`, `lib/sesh_lab*` -> `lib/aponte*`, `_sesh_lab_key` cookie -> `_aponte_key`, esbuild profile `sesh_lab` -> `aponte`, `SeshLab.WebPush.Finch` -> `Aponte.WebPush.Finch`, mix task `sesh.gen.vapid` -> `aponte.gen.vapid` (module `Mix.Tasks.Aponte.Gen.Vapid`), basic-auth realm `"sesh sesh"` -> `"aponte"`, coupon prefix `"SESH-"` -> `"APO-"`.

### New modules

**`Aponte.Orgs.Org`** (`lib/aponte/orgs/org.ex`, core schema):
```elixir
schema "orgs" do
  field :slug, :string
  field :name, :string
  field :about, :string
  field :accent_color, :string, default: "#F07BC0"
  field :logo_path, :string
  field :instagram, :string
  field :pix_key, :string
  field :status, Ecto.Enum, values: [:active, :suspended], default: :active
  field :tier, Ecto.Enum, values: [:free, :paid], default: :free
  field :storage_quota_bytes, :integer, default: 52_428_800
  field :social_links, {:array, :map}, default: []

  has_many :editions, Aponte.Editions.Edition
  has_many :images, Aponte.Orgs.OrgImage
  timestamps()
end
```
Changeset: `validate_required([:slug, :name])`, slug format `~r/^[a-z0-9][a-z0-9-]{1,31}$/`, `update_change(:slug, &String.downcase/1)`, reserved-slug validation (`validate_change` against `Orgs.reserved_slugs/0`), accent hex format (copy from Edition), `unique_constraint(:slug)`. Social links validated by a custom `validate_change(:social_links, ...)` requiring every entry to be a map with non-empty `"label"` and `"url"` keys (pattern match on shape, no validator lib).

**`Aponte.Orgs.OrgImage`** (`lib/aponte/orgs/org_image.ex`): schema matching M8; changeset validates required `[:org_id, :path, :thumb_path, :content_hash, :byte_size]` and `unique_constraint([:org_id, :content_hash])`.

**`Aponte.Orgs`** (`lib/aponte/orgs.ex`, context; shell except pure slug/quota helpers):
```elixir
@reserved ~w(sobre admin api uploads dev assets images fonts live phoenix
             robots.txt sitemap.xml manifest.webmanifest sw.js favicon.ico aponte)

@spec reserved_slugs() :: [String.t()]
@spec get_org_by_slug(String.t()) :: {:ok, Org.t()} | {:error, :not_found}
  # {:error, :not_found} for unknown, reserved, or non-:active slugs.
@spec get_org!(Ecto.UUID.t()) :: Org.t()
@spec list_active_orgs() :: [Org.t()]
@spec list_orgs_with_current_edition() :: [{Org.t(), Edition.t() | nil}]
  # Two queries total (orgs + published editions), zipped by org_id. No N+1.
@spec create_org(map()) :: {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
@spec update_org(Org.t(), map()) :: {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
@spec change_org(Org.t(), map()) :: Ecto.Changeset.t()

# Gallery
@spec list_images(Ecto.UUID.t()) :: [OrgImage.t()]              # by position asc
@spec add_image(Org.t(), %{path: ..., thumb_path: ..., content_hash: ..., byte_size: ..., original_filename: ...}) ::
        {:ok, OrgImage.t()} | {:error, :duplicate | Ecto.Changeset.t()}
@spec delete_image(OrgImage.t()) :: {:ok, OrgImage.t()}         # caller deletes files
@spec reorder_images(Ecto.UUID.t(), [Ecto.UUID.t()]) :: :ok     # position = index, one transaction

# Quota (pure given the sum; sum query is the shell)
@spec storage_used_bytes(Ecto.UUID.t()) :: non_neg_integer()    # sum(byte_size)
@spec check_upload_quota(Org.t(), non_neg_integer(), keyword()) ::
        {:ok, :within_quota} | {:ok, :over_quota} | {:error, :over_quota}
  # opts[:enforce?] default false: over-quota returns {:ok, :over_quota} (warn, allow).
  # enforce?: true returns {:error, :over_quota}.
@spec over_quota?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  # pure: over?(used, incoming, quota)
```

**`Aponte.Images`** (`lib/aponte/images.ex`) + behaviour **`Aponte.Images.Processor`**:
```elixir
# lib/aponte/images/processor.ex
@callback process(source_path :: Path.t(), dest_dir :: Path.t(), basename :: String.t()) ::
  {:ok, %{web: String.t(), thumb: String.t(), byte_size: non_neg_integer()}} | {:error, term()}
```
- `Aponte.Images.Vips` impl: uses `Image.open!/1`, `Image.thumbnail/2` (1600px web, 400px thumb), writes `<basename>.webp` and `<basename>_thumb.webp` into `dest_dir` (basename = content hash). `byte_size` = sum of both files. Reject non-images upstream via `Image.open` error -> `{:error, :invalid_image}`.
- `Aponte.Uploads` (`lib/aponte/uploads.ex`, no behaviour): `root/0` (config `:aponte, :uploads_dir`, same semantics as today), `org_dir(org_id)`, `ensure_dirs!(org_id)`, `content_hash(path)` (sha256 hex of file, streamed), `delete_quiet(path)`. `Aponte.Application.start` calls `Uploads.ensure_dirs!/0` for the root only (per-org dirs created lazily at upload).
- Config: `config :aponte, :image_processor, Aponte.Images.Vips` in config.exs; `Aponte.Images.Fake` in test.exs. Fake writes the source bytes to both variant paths (no vips needed in test) and returns correct shapes.

**`AponteWeb.Plugs.LoadOrg`** (`lib/aponte_web/plugs/load_org.ex`): `@behaviour Plug`. Reads `conn.path_params["org_slug"]`; `Orgs.get_org_by_slug/1` -> `assign(conn, :org, org)`; on `{:error, :not_found}` sends 404 via `AponteWeb.ErrorHTML` and halts. Used in both public and admin org scopes.

**`AponteWeb.Plugs.Accent`** (changed): no longer queries `Editions.current_accent/0`. Reads `conn.assigns[:org]`: assigns `:accent` = `org.accent_color` when present, else the Aponte default (`Application.get_env(:aponte, :default_accent, "#BF7262")`). Controllers may still override per page (comprar already re-assigns the edition's accent). Must run **after** LoadOrg: remove it from `:browser`, add `plug Plugs.Accent` explicitly in each scope after the loader (and standalone in Aponte-level scopes).

**`AponteWeb.Plugs.RedirectLegacyHost`** (`lib/aponte_web/plugs/redirect_legacy_host.ex`): endpoint plug placed before `AponteWeb.Router`. Config `config :aponte, :legacy_host_redirects, %{"sesh-lab.fly.dev" => "aponte.live"}` (prod only; empty map disables). On host match: 301 to `https://<target><request_path><?query>`, halt. This is the whole old-domain strategy: one app serves both hostnames during the window; remove config + plug when the old domain dies.

**`AponteWeb.UploadController`** (`lib/aponte_web/controllers/upload_controller.ex`): `GET /uploads/*path`. Rejects any segment in `["..", ""]`, joins under `Uploads.root()`, `send_file(conn, 200, abs)` with headers `cache-control: public, max-age=31536000, immutable` and content-type via `MIME.from_path/1`. 404 when missing. **Replaces** the `Plug.Static, at: "/uploads"` plug in endpoint.ex (delete it; keep only the priv/static plug). Route lives outside `:browser` (no session/csrf needed for GET).

**Admin org LiveViews:**
- `AponteWeb.Admin.OrgListLive` (`/admin`): lists orgs, link to `/admin/organizacoes/nova`.
- `AponteWeb.Admin.OrgFormLive` (`/admin/organizacoes/nova`, `/admin/:org_slug/perfil`): create/edit org (name, slug on create only, about, accent, logo upload, instagram, pix_key, social_links as label+url row list). Logo upload reuses the gallery pipeline (hash + store under `orgs/:org_id/`), svg allowed and stored raw (no vips for svg: if content-type is svg, copy as-is and use same path for thumb).
- `AponteWeb.Admin.OrgGalleryLive` (`/admin/:org_slug/galeria`): `allow_upload(:images, accept: ~w(.jpg .jpeg .png .webp), max_entries: 10, max_file_size: 5_000_000)`; consume -> `Uploads.content_hash/1` -> `Processor.process` -> `Orgs.check_upload_quota/3` (soft: flash warning when `{:ok, :over_quota}`, still insert) -> `Orgs.add_image/2`. List with thumbnails, delete (row + files), reorder (up/down buttons emitting an id list; drag is out of scope).

**`AponteWeb.OrgHooks`** (`lib/aponte_web/org_hooks.ex`): `on_mount(:load_org, params, _session, socket)` — fetches org by `params["org_slug"]`, `{:halt, redirect(socket, to: "/admin")}` on miss; assigns `:org`. Registered via `live_session :admin, on_mount: [{AponteWeb.OrgHooks, :load_org}]`.

### Changed contexts (signatures the implementer must follow)

**`Aponte.Editions`** — org scope added to every list/current function; schema gains `org_id` (belongs_to :org, cast+required), `ends_at` (`:utc_datetime`, nullable, `validate ends_at > starts_at when present`):
```elixir
@spec list_editions(Ecto.UUID.t()) :: [Edition.t()]
@spec current_edition(Ecto.UUID.t()) :: Edition.t() | nil
@spec current_accent(Ecto.UUID.t()) :: String.t() | nil
@spec get_edition_in_org(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Edition.t()} | {:error, :not_found}
@spec create_edition(Org.t(), map()) :: {:ok, Edition.t()} | {:error, Ecto.Changeset.t()}  # puts org_id
@spec publish(Edition.t()) :: {:ok, Edition.t()} | {:error, Ecto.Changeset.t()}
  # update_all now: where e.status == :published and e.org_id == ^edition.org_id
```
`Edition.changeset` unique constraint: `unique_constraint([:org_id, :number])`. `maybe_default_name` becomes `"#{org.name} ##{n}"` — pass org name in via changeset option or set name in `create_edition` before changeset (simplest: set default name in context when `name` blank, drop the changeset private fn's hardcoded "SESH").

**`Aponte.Tickets`**:
```elixir
@spec create_order(Org.t(), map()) :: {:ok, Order.t()} | {:error, ...}   # unchanged error union
  # put_attr(:org_id, org.id); pix_key snapshot comes from org.pix_key
  # preload_merch(items, org.id) — adds where m.org_id == ^org_id (blocks cross-org item injection)
  # NEW validation: every ticket_type must belong to attrs[:edition_id] whose org_id == org.id,
  #   else {:error, {:unknown_ticket_type, id}}. Closes a pre-existing cross-edition hole.
@spec issue_confirmed(comp_input(), keyword()) :: ...   # comp_input gains required :org_id
@spec lookup_order(Ecto.UUID.t(), String.t(), String.t()) :: {:ok, Order.t()} | {:error, :not_found}
  # org_id, normalized phone, order id (the "code"). Single order by id where org + phone match.
  # NEVER lists by phone alone.
@spec list_recent(Ecto.UUID.t(), non_neg_integer()) :: [Order.t()]   # org_id first arg
@spec list_pending(Ecto.UUID.t()) :: [Order.t()]
@spec search_orders(Ecto.UUID.t(), String.t(), keyword()) :: [Order.t()]
```
`stats/1`, `stats_by_type/1`, `confirm_order/2`, `cancel_order/1`, `validate_ticket/1` stay id/code-scoped (callers already resolved edition inside the org); `insert_ticket!` gains `org_id: order.org_id`.

**`Aponte.Tickets.Order` schema**: `customer_phone :string` added; `customer_instagram` optional; `belongs_to :org`. Changeset:
```elixir
|> update_change(:customer_phone, &normalize_phone/1)   # digits only: String.replace(~r/\D/, "")
|> validate_length(:customer_phone, min: 10, max: 13)
|> validate_contact()  # custom: at least one of customer_instagram / customer_phone present,
                       # error on :customer_instagram "informe instagram ou WhatsApp"
```
`validate_format(:customer_instagram, ...)` only applied when non-nil. New pure helpers:
```elixir
@spec normalize_phone(String.t() | nil) :: String.t() | nil
@spec masked_name(String.t()) :: String.t()   # "Maria Silva" -> "M. S." (initial per word, upcased)
```

**`Aponte.Merch`**: `list_items(org_id)`, `list_active_items(org_id)`, `list_counter_items(org_id)`, `get_counter_items(org_id, ids)`, `create_item(org, attrs)` (puts org_id). `list_featured_items(edition_id)` unchanged (edition implies org). `Item` schema gains `belongs_to :org` (cast+required).

**`Aponte.Coupons`**: `list_rules(org_id)`, `list_active_rules(org_id)`, `list_coupons(org_id)`, `list_public_coupons(org_id)`, `create_public_coupon(org, attrs)`, `create_rule(org, attrs)`. `preview(code, ctx)` — `ctx` gains `:org_id`; `get_by_code(org_id, code)` scopes the lookup. `issue_for_order/1` returns `:ok` immediately when `order.customer_instagram` is nil; bound coupon insert gains `org_id: order.org_id`. `claim/3` unchanged (id-scoped, already inside the order transaction).

**`Aponte.Notifications`**: `PushSubscription` schema gains nullable `org_id`. `subscribe/1` casts it (org-scoped subscribe endpoint passes it). `announce_edition/1` targets client subs `where org_id == ^edition.org_id`; Aponte-wide announcements (future) target `is_nil(org_id)`. Admin audience subs keep `org_id` nil. Payload URLs become org-aware: `"url" => "/#{org.slug}/compra/#{order.id}"` and `"/admin/#{org.slug}/pedidos/#{order.id}"` — `notify_admin_new_order` and `notify_customer_order_update` must preload `order.org` (add `belongs_to :org` on Order and `Repo.preload(:org)` in `preload_items`, renamed `preload_for_notify`).

**`Aponte.DjApplications`**: `create(org, attrs)` (puts org_id), `list(org_id)`.

**`Aponte.Bar`**: unchanged signatures; `BalcaoLive` passes the org-scoped current edition. `Bar.stats(edition_id)` unchanged.

**`Aponte.Settings`**: unchanged (global KV).

**`Aponte.Backfill`**: `issue_confirmed` input gains `org_id` (from the edition it already loads); `order_url` becomes `"/#{org_slug}/compra/#{id}"`.

**`AponteWeb.SEO`**: `@site_name "Aponte"`; `music_event_jsonld` organizer name becomes the org name (add a `org_name` param or take the edition preloaded with org).

## 5. Router diff

```elixir
pipeline :browser do
  # ... unchanged minus Accent ...
  plug :put_secure_browser_headers
end

pipeline :load_org do
  plug AponteWeb.Plugs.LoadOrg
  plug AponteWeb.Plugs.Accent
end

pipeline :lookup_rate_limit do
  plug AponteWeb.Plugs.RateLimit, max: 10, window_ms: 3_600_000, bucket: "meus-ingressos"
end

# uploads (outside :browser)
scope "/", AponteWeb do
  get "/uploads/*path", UploadController, :show
end

# Aponte-level
scope "/", AponteWeb do
  pipe_through [:browser, AponteWeb.Plugs.Accent]
  get "/", PageController, :index              # orgs + current/upcoming published edition each
  get "/sobre", PageController, :sobre         # Aponte about
  get "/robots.txt", SeoController, :robots
  get "/sitemap.xml", SeoController, :sitemap
end

# TEMPORARY legacy path redirects on the new domain (removal trigger: 30 days post-cutover)
scope "/", AponteWeb do
  pipe_through :browser
  get "/comprar", LegacyRedirect, to: "/sesh/comprar"          # implement as one controller
  get "/compra/:id", LegacyRedirect, to: "/sesh/compra/:id"    # action building target from params
  get "/meus-ingressos", LegacyRedirect, to: "/sesh/meus-ingressos"
  get "/loja", LegacyRedirect, to: "/sesh/loja"
  get "/avisos", LegacyRedirect, to: "/sesh/avisos"
  get "/tocar", LegacyRedirect, to: "/sesh/tocar"
end

# Org-scoped public
scope "/:org_slug", AponteWeb do
  pipe_through [:browser, :load_org]
  get "/", OrgController, :show                # vitrine: flyer + gallery + about + socials
  get "/comprar", OrderController, :new
  post "/comprar", OrderController, :create
  get "/compra/:id", OrderController, :show    # 404 unless order.org_id == org.id
  get "/meus-ingressos", OrderController, :history
  get "/loja", LojaController, :index
  post "/loja", LojaController, :create
  get "/avisos", PageController, :avisos
  get "/tocar", DjController, :new
end

scope "/:org_slug", AponteWeb do
  pipe_through [:browser, :load_org, :lookup_rate_limit]
  post "/meus-ingressos", OrderController, :lookup
end

scope "/:org_slug", AponteWeb do
  pipe_through [:browser, :load_org, :dj_rate_limit]
  post "/tocar", DjController, :create
end

# Push: org-scoped subscribe + keep global for Aponte-wide (org_id nil)
scope "/:org_slug", AponteWeb do
  pipe_through [:client_api, :load_org_api]    # variant of LoadOrg returning JSON 404
  get "/push/vapid-key", PushController, :vapid_key
  post "/push/subscribe", PushController, :subscribe   # org_id from assigns
  get "/push/subscribe", PushController, :show
  patch "/push/subscribe", PushController, :update
  delete "/push/subscribe", PushController, :unsubscribe
end
scope "/", AponteWeb do
  pipe_through :client_api
  get "/push/vapid-key", PushController, :vapid_key
  post "/push/subscribe", PushController, :subscribe   # org_id nil (Aponte-wide)
  # show/update/delete shared by endpoint, not org-scoped
  get "/push/subscribe", PushController, :show
  patch "/push/subscribe", PushController, :update
  delete "/push/subscribe", PushController, :unsubscribe
end

# Admin
scope "/admin", AponteWeb do
  pipe_through [:browser, :admin]
  live "/", Admin.OrgListLive, :index
  live "/organizacoes/nova", Admin.OrgFormLive, :new
end

scope "/admin/:org_slug", AponteWeb, as: :admin do
  pipe_through [:browser, :admin, :load_org]

  live_session :admin, on_mount: [{AponteWeb.OrgHooks, :load_org}] do
    live "/", Admin.DashboardLive, :index
    live "/perfil", Admin.OrgFormLive, :edit
    live "/galeria", Admin.OrgGalleryLive, :index
    live "/edicoes/nova", Admin.EditionFormLive, :new
    live "/edicoes/:id", Admin.EditionFormLive, :edit
    live "/edicoes/:id/cortesia", Admin.CortesiaLive, :index
    live "/pedidos/:id", Admin.OrderShowLive, :show
    live "/buscar", Admin.OrderSearchLive, :index
    live "/validar", Admin.ScannerLive, :index
    live "/validar/:edition_id", Admin.ScannerLive, :index
    live "/tocar", Admin.DjApplicationsLive, :index
    live "/cupons", Admin.CouponsLive, :index
    live "/cupons/novo", Admin.CouponFormLive, :new
    live "/cupons/regras/nova", Admin.CouponRuleFormLive, :new
    live "/cupons/regras/:id", Admin.CouponRuleFormLive, :edit
    live "/cupons/:id", Admin.CouponFormLive, :edit
    live "/produtos", Admin.ProductsLive, :index
    live "/produtos/novo", Admin.ProductFormLive, :new
    live "/produtos/:id", Admin.ProductFormLive, :edit
    live "/balcao", Admin.BalcaoLive, :index
  end
end

scope "/admin/:org_slug", AponteWeb do
  pipe_through [:admin_api, :load_org]
  get "/push/vapid-key", Admin.PushController, :vapid_key
  post "/push/subscribe", Admin.PushController, :subscribe
  delete "/push/subscribe", Admin.PushController, :unsubscribe
end
```

Notes:
- Reserved slugs are enforced in **two** places: `Org.changeset` (cannot create) and `LoadOrg` (404 even if a row somehow exists). Route literal matching alone is not sufficient because Phoenix would match a registered org slug named e.g. `sobre` before... actually literals win by definition order, but the reserved list protects against future route reordering and slug squatting. Keep both.
- Every admin LiveView `mount` that today calls global functions now reads `socket.assigns.org` (from the on_mount hook): `Editions.list_editions(org.id)`, `Tickets.list_pending(org.id)`, `Merch.list_items(org.id)`, `Editions.current_edition(org.id)` (BalcaoLive/ScannerLive), etc. Edition-loading routes (`/edicoes/:id`, `/validar/:edition_id`, `/cortesia`) must load via `Editions.get_edition_in_org(org.id, id)` and halt-redirect on `:not_found` — this is the cross-org URL-tampering guard.
- Layouts: `Layouts.app` gains an optional `@org` assign; nav links become `~p"/#{@org.slug}/loja"` etc when present, and the Aponte shell (home/sobre) renders brand-only nav. `Layouts.admin` `back_to` default becomes `"/admin/#{org.slug}"`.

## 6. Rename strategy (ordered, bootable at every step)

Do the rename as its own PR + deploy, **before** the org refactor. Each step compiles and boots:

1. `git mv lib/sesh_lab lib/aponte && git mv lib/sesh_lab_web lib/aponte_web` and same under `test/`.
2. Global `SeshLab` -> `Aponte`, `sesh_lab` -> `aponte` across `lib/`, `test/`, `config/`, `mix.exs`, `priv/repo/seeds.exs`, `.formatter.exs` if referenced. This covers: OTP app name (`app: :aponte`, `mod: {Aponte.Application, []}`), Repo (`Aponte.Repo`), PubSub name, Finch name, all `Application.get_env/fetch_env(:sesh_lab, ...)` keys, endpoint `otp_app`, esbuild profile name + `assets.build`/`assets.deploy` aliases, cookie key `_aponte_key`, basic-auth realm.
3. `mix.exs` `mix sesh.gen.vapid` -> file `lib/mix/tasks/aponte.gen.vapid.ex`, module `Mix.Tasks.Aponte.Gen.Vapid`.
4. Config: `config/runtime.exs` comment examples; `config/config.exs` vapid subject `mailto:contato@aponte.live` (placeholder until domain exists); prod `check_origin: ["https://aponte.live", "https://www.aponte.live"]`; `PHX_HOST` default `"aponte.live"`.
5. fly.toml: **keep `app = "sesh-lab"` and `source = "sesh_data"`** (volume and machine are bound to the Fly app name; renaming the Fly app means recreating the volume and moving the DB — not worth it). Update `PHX_HOST = "aponte.live"` env. Add a comment: "Fly app name stays sesh-lab; the volume is attached to it."
6. Check `Dockerfile` for the release binary name (`bin/sesh_lab` -> `bin/aponte`) and any `RELEASE_NAME`. (Not read here; the implementer must grep it.)
7. Static/PWA: `priv/static/manifest.webmanifest` `name`/`short_name` -> "Aponte"; `assets/js/sw.js` cache-name constant bumped (`sesh-*` -> `aponte-v1`) so old caches are abandoned; `SeshLabWeb.SEO` site name. Push subscriptions die with the origin — accepted, no migration.
8. Tests: rename namespaces, `test/support` cases; cookie/session assertions if any.
9. Deploy. App serves both `sesh-lab.fly.dev` (Fly default, cannot be removed) and, after `fly certs add aponte.live aponte.live` + `fly certs add www.aponte.live`, the new domain.

Then the org refactor PR lands on top, ending with the migration deploy that still has `PIX_KEY` set (M1 reads it). After that deploy verifies, `PIX_KEY` and `MERCHANT_NAME` envs may be removed (`fly secrets unset`); keep `MERCHANT_CITY`.

Domain cutover sequencing: buy aponte.live -> `fly certs add` both names -> point DNS (A/AAAA to the app, or CNAME to `sesh-lab.fly.dev`) -> deploy with `PHX_HOST=aponte.live` + `legacy_host_redirects` config -> verify -> announce -> after the window (30 days), remove `legacy_host_redirects` config, the `LegacyRedirect` routes, and let `sesh-lab.fly.dev` 404 via the same plug removal (the fly.dev subdomain itself cannot be deleted, so the plug is what makes it "die" — removing the plug entry makes it serve the app under the old host; if a hard die is wanted, keep the plug but switch its response to 410. Decision: switch to 410 after the 301 window, one-line config value `status: 301 | 410`).

## 7. Vitrine / uploads / identity details

**Org page (`OrgController.show`)**: loads org (assigns), current published edition (flyer block, may be nil), `Orgs.list_images(org.id)` rendered below the flyer (thumb grid, click opens web variant), `org.about`, `org.social_links`, instagram/pix display. SEO description from `org.about` truncated.

**Upload flow (shell order, all in `OrgGalleryLive.handle_event("save")` via `consume_uploaded_entries`):**
1. `Uploads.content_hash(tmp_path)` -> basename.
2. `Orgs.check_upload_quota(org, byte_size_of_entry, enforce?: false)` -> flash warn on over.
3. `Processor.process(tmp_path, Uploads.org_dir(org.id), hash)` (Vips: 1600px web webp + 400px thumb webp; svg bypasses vips, copied raw).
4. `Orgs.add_image(org, attrs)` -> on `{:error, :duplicate}` flash "imagem ja enviada".
In-request is deliberate: 5 MB cap, admin-only, a few at a time. Trigger to move to Oban: bulk uploads or processing p95 over ~2 s.

**meus-ingressos**: `GET` renders the shell (existing localStorage list stays — it is device-local and free) **plus** the new lookup form (phone + order code). `POST` (rate-limited) -> `Tickets.lookup_order(org.id, phone, code)` -> renders the single order card with `Order.masked_name(order.customer_name)`, status, and a link to `/:slug/compra/:id`. Not found: generic "nada encontrado" (no oracle on which field failed). `assets/js/orders.js` must build `/compra/` links from a `data-org-slug` attribute on the container, and its import-input regex must accept `/<slug>/compra/<uuid>`.

**`client_push.js`**: hardcoded `"/push/..."` constants become reads from `data-push-vapid-url` / `data-push-sub-url` attributes rendered by the avisos page (org-scoped when under an org, global on the Aponte avisos page if one is kept — decision: avisos exists only under org scope in v1; Aponte-wide subscribe UI deferred).

## 8. Test seam

- **`Aponte.Images.Processor` Fake** (test/support, configured in `config/test.exs`): copies bytes, returns `%{web:, thumb:, byte_size:}`. No vips needed to run the suite.
- **Storage**: `config :aponte, :uploads_dir, System.tmp_dir!() <> "/aponte_test_uploads"` in test.exs with per-test cleanup in DataCase/ConnCase setup. No storage behaviour — the filesystem in tmp is already deterministic.
- **Context tests (the invariants that matter):**
  1. **Scoping leakage**: fixture two orgs with editions/orders/merch/coupons each; assert `list_editions`, `current_edition`, `list_recent`, `list_pending`, `search_orders`, `list_active_items`, `list_coupons`, `DjApplications.list` return only their org's rows; assert `publish` archives only same-org published editions (other org's published untouched).
  2. **Cross-org injection**: `create_order(org_a, %{items: [%{merch_item_id: item_from_b, ...}]})` -> `{:error, {:unknown_merch_item, _}}`; same for a ticket_type from org B's edition.
  3. **Identity**: changeset invalid with neither instagram nor phone; valid with either; phone normalized (`"(22) 99876-5432" -> "22998765432"`); existing-style instagram-only orders still validate.
  4. **lookup_order**: matches only on (org, phone, id) triple; wrong org with right phone+id -> `:not_found`; wrong phone -> `:not_found`; no list-by-phone function exists (compile-level: there is no such public function).
  5. **Quota**: `check_upload_quota` pure core (`over_quota?/3`) at boundary values; soft flag allows, `enforce?: true` errors.
  6. **Coupons**: `preview` with org B's code in org A context -> `{:error, :not_found}`; phone-only order earns no bound coupon.
  7. **LoadOrg plug**: 404 on unknown slug, reserved slug, suspended org; assigns on hit.
  8. **Rate limit conn test**: 11th POST to `/:slug/meus-ingressos` within the window -> 429 (follow the existing dj_rate_limit test pattern if one exists, else bucket-isolated ETS key per test).
  9. **get_edition_in_org**: org A admin URL with org B's edition id -> `:not_found` (LiveView halt redirect test).
- Existing suites (tickets race test, coupons, bar) need only mechanical updates for the new first-arg org / org_id fixture fields; behavior assertions stay.

## 9. Deferred (triggers named)

- `org_memberships` / producer accounts / session auth: **trigger = first external producer.** The BasicAuth plug and LoadOrg are the only auth seams; swap there.
- Per-edition publish paywall + fatura flow: **trigger = first external paying producer.** `orgs.tier` exists from day one precisely for this.
- Hard quota enforcement: **trigger = any org hitting soft quota twice** (flip `enforce?: true` in the gallery; the check function already takes the flag).
- `check_ins` multi-day table: **trigger = first two-day event.** `editions.ends_at` is in place; nothing else pre-built.
- Aponte-wide push subscribe UI + announcement tooling: **trigger = Aponte itself wanting to broadcast** (schema supports `org_id IS NULL` already).
- S3/off-disk storage: **trigger = volume size > 1 GiB or multi-machine.** Single machine + SQLite makes local disk correct now.
- Oban for image processing: **trigger = bulk uploads or slow processing** (see 7).
- Per-org `dj_applications_open` flag: **trigger = second org with its own tocar schedule.**
- Discovery/categories/tags, theme engine beyond accent/logo/about/gallery, OTP/verification, barraquinha/vendor features: no trigger accepted yet.

## 10. What the designer pushed back on / flagged

- **Denormalized `org_id` on orders/tickets is worth it** (single-index tenant filter on the hottest admin queries, no join through editions), but it makes `org_id` a write-time invariant: every insert path (`create_order`, `issue_confirmed`, `insert_ticket!`) must set it explicitly. The spec centralizes this: org comes from the context argument, never from user params (`put_attr` pattern already used for pix_key).
- **Do not rename the Fly app or volume.** Keep `app = "sesh-lab"` in fly.toml. Only PHX_HOST, certs, and check_origin change. This is the cheapest cutover and keeps `/data/sesh.db` exactly where it is.
- **The `{:array, :map}` social_links column is the deliberate SQLite-pragmatic choice** over a join table: max a handful of links, edited inline with the org form, never queried relationally. If a future need to query by link type appears, that is the trigger for a table.
- **Route-order trap to respect during implementation**: `/admin/organizacoes/nova` must live in the `/admin` scope defined **before** `/admin/:org_slug`, or `organizacoes` will be swallowed as an org slug. Same for public literals vs `/:org_slug`. The reserved-slug list is the second net, not the first.
