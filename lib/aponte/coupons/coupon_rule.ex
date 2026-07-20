defmodule Aponte.Coupons.CouponRule do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "coupon_rules" do
    belongs_to :org, Aponte.Orgs.Org, type: :binary_id

    field :name, :string
    field :min_order_cents, :integer
    field :discount_kind, Ecto.Enum, values: [:percent, :fixed]
    field :discount_value, :integer
    field :expires_in_days, :integer, default: 7
    field :is_active, :boolean, default: true

    timestamps()
  end

  @castable ~w(org_id name min_order_cents discount_kind discount_value expires_in_days is_active)a
  @required ~w(name min_order_cents discount_kind discount_value)a

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_number(:min_order_cents, greater_than: 0)
    |> validate_number(:expires_in_days, greater_than: 0)
    |> Aponte.Coupons.Coupon.validate_discount()
  end
end
