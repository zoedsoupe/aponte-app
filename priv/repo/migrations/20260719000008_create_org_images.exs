defmodule Aponte.Repo.Migrations.CreateOrgImages do
  use Ecto.Migration

  def change do
    create table(:org_images, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false

      # Web variant filename, content-hashed.
      add :path, :string, null: false
      add :thumb_path, :string, null: false
      add :original_filename, :string
      # sha256 hex of the original upload.
      add :content_hash, :string, null: false
      add :position, :integer, null: false, default: 0
      # Web + thumb bytes (real disk usage).
      add :byte_size, :integer, null: false
      timestamps(updated_at: false)
    end

    create index(:org_images, [:org_id])
    # Re-uploading the same file dedups.
    create unique_index(:org_images, [:org_id, :content_hash])
  end
end
