defmodule Aponte.Tickets.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aponte.Tickets.{OrderItem, Ticket}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    belongs_to :org, Aponte.Orgs.Org

    field :status, Ecto.Enum,
      values: [:pending, :confirmed, :cancelled, :expired],
      default: :pending

    field :edition_id, :binary_id
    field :customer_name, :string
    field :customer_instagram, :string
    field :customer_phone, :string
    field :total_cents, :integer
    field :coupon_code, :string
    field :discount_cents, :integer, default: 0
    field :pix_key, :string
    # Push endpoint of the device that placed the order (for status notifications).
    field :client_endpoint, :string

    has_many :items, OrderItem, foreign_key: :order_id, on_delete: :delete_all
    has_many :tickets, Ticket, foreign_key: :order_id, on_delete: :delete_all
    has_many :merch_units, Aponte.Merch.Unit, foreign_key: :order_id, on_delete: :delete_all

    timestamps()
  end

  @castable ~w(org_id edition_id customer_name customer_instagram customer_phone total_cents
               coupon_code discount_cents status pix_key client_endpoint)a
  @required ~w(customer_name total_cents)a

  def changeset(order, attrs) do
    order
    |> cast(attrs, @castable)
    |> update_change(:customer_instagram, &normalize_handle/1)
    |> update_change(:customer_phone, &normalize_phone/1)
    |> blank_to_nil(:customer_instagram)
    |> blank_to_nil(:customer_phone)
    |> validate_required(@required)
    # Belt to to_int/1's suspenders: no order can be created with a negative
    # total regardless of the insert path used for its items.
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
    |> validate_length(:customer_name, min: 2, max: 80)
    |> validate_length(:customer_instagram, min: 1, max: 30)
    |> validate_format(:customer_instagram, ~r/^[a-z0-9._]+$/,
      message: "use apenas letras, números, ponto ou underline"
    )
    |> validate_length(:customer_phone, min: 10, max: 13)
    |> validate_contact()
  end

  # Buyer identity is "instagram OR phone": at least one must be present.
  defp validate_contact(changeset) do
    case {get_field(changeset, :customer_instagram), get_field(changeset, :customer_phone)} do
      {instagram, phone} when instagram in [nil, ""] and phone in [nil, ""] ->
        add_error(changeset, :customer_instagram, "informe instagram ou WhatsApp")

      _ ->
        changeset
    end
  end

  defp blank_to_nil(changeset, field) do
    case get_change(changeset, field) do
      "" -> put_change(changeset, field, nil)
      _ -> changeset
    end
  end

  @doc "Normaliza handle do Instagram: trim, remove @ inicial, lowercase."
  def normalize_handle(nil), do: nil

  def normalize_handle(handle) do
    handle |> String.trim() |> String.trim_leading("@") |> String.downcase()
  end

  @doc "Phone as digits only (strips formatting like `(22) 99876-5432`)."
  @spec normalize_phone(String.t() | nil) :: String.t() | nil
  def normalize_phone(nil), do: nil
  def normalize_phone(phone), do: String.replace(phone, ~r/\D/, "")

  @doc ~S|Nome mascarado pra exibição pública: "Maria Silva" -> "M. S."|
  @spec masked_name(String.t()) :: String.t()
  def masked_name(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", fn word -> String.upcase(String.first(word)) <> "." end)
  end
end
