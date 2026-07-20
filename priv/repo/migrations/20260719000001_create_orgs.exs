defmodule Aponte.Repo.Migrations.CreateOrgs do
  use Ecto.Migration

  def change do
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

    # Seed the single existing org. PIX_KEY is snapshotted from the deploy env
    # (may be NULL; backfill with one UPDATE via `fly ssh console` if absent).
    execute(&seed_sesh_org/0, &drop_sesh_org/0)
  end

  defp seed_sesh_org do
    now =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    repo().query!(
      "INSERT INTO orgs (id, slug, name, accent_color, pix_key, inserted_at, updated_at) VALUES (?, 'sesh', 'SESH', '#F07BC0', ?, ?, ?)",
      [Ecto.UUID.generate(), System.get_env("PIX_KEY"), now, now]
    )
  end

  defp drop_sesh_org do
    repo().query!("DELETE FROM orgs WHERE slug = 'sesh'", [])
  end
end
