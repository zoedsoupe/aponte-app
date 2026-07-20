defmodule Aponte.Repo.Migrations.AddOrgIdColumns do
  use Ecto.Migration

  # All columns nullable here; M3 backfills and M4-M7 rebuild the hot tables
  # with NOT NULL. push_subscriptions/dj_applications stay nullable forever
  # (admin subs and pre-orgs rows have no tenant).
  def change do
    for table <- ~w(editions orders tickets merch_items coupons coupon_rules)a do
      alter table(table) do
        add :org_id, references(:orgs, type: :binary_id, on_delete: :restrict)
      end

      create index(table, [:org_id])
    end

    for table <- ~w(push_subscriptions dj_applications)a do
      alter table(table) do
        add :org_id, references(:orgs, type: :binary_id, on_delete: :nilify_all)
      end

      create index(table, [:org_id])
    end
  end
end
