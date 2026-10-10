defmodule Aponte.Repo.Migrations.ScopePushSubscriptionsPerOrg do
  use Ecto.Migration

  # A device could only hold one subscription (unique on endpoint), so
  # subscribing under a second org silently moved the device off the first.
  # Key uniqueness on (endpoint, audience, COALESCE(org_id, '')) instead: one
  # row per org for clients, and admin / Aponte-wide subs (NULL org) still
  # dedupe by endpoint.
  def up do
    drop_if_exists unique_index(:push_subscriptions, [:endpoint])

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS push_subscriptions_endpoint_audience_org_index
    ON push_subscriptions (endpoint, audience, COALESCE(org_id, ''))
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS push_subscriptions_endpoint_audience_org_index")
    create unique_index(:push_subscriptions, [:endpoint])
  end
end
