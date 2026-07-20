defmodule Aponte.Repo.Migrations.BackfillOrgIds do
  use Ecto.Migration

  # Single org ("sesh") exists at this point, so a plain subselect backfills
  # every table — including pure-merch orders (edition_id IS NULL).
  def up do
    for table <-
          ~w(editions orders tickets merch_items coupons coupon_rules
             push_subscriptions dj_applications) do
      repo().query!("UPDATE #{table} SET org_id = (SELECT id FROM orgs WHERE slug = 'sesh')", [])
    end
  end

  def down, do: raise("irreversible: org_id backfill")
end
