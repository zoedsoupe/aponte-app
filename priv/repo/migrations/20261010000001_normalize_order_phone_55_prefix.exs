defmodule Aponte.Repo.Migrations.NormalizeOrderPhone55Prefix do
  use Ecto.Migration

  # Orders created before normalize_phone/1 started collapsing the +55 prefix
  # may store the country code (12/13 digits starting with "55"). Bring them to
  # the local form so meus-ingressos lookup matches regardless of how the buyer
  # typed the number. Only 12/13-digit values are touched; DDD 55 numbers are
  # 10/11 digits and stay intact.
  def up do
    execute("""
    UPDATE orders
    SET customer_phone = substr(customer_phone, 3)
    WHERE length(customer_phone) IN (12, 13) AND customer_phone LIKE '55%'
    """)
  end

  def down do
    :ok
  end
end
