defmodule Aponte.Repo.Migrations.AddOrgThemeColors do
  use Ecto.Migration

  def change do
    alter table(:orgs) do
      # Per-org theme levers. NULL derives from the Aponte platform palette
      # (bg #FEF8DA / ink #49422F) in Plugs.Accent.
      add :bg_color, :string
      add :fg_color, :string
    end
  end
end
