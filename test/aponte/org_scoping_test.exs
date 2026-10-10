defmodule Aponte.OrgScopingTest do
  @moduledoc """
  Tenant-isolation invariants (spec section 8): no listing leaks across orgs,
  no cross-org injection at order creation, buyer lookup matches the exact
  (org, phone, id) triple, and coupon redemption is org-scoped.
  """

  use Aponte.DataCase, async: false

  import Aponte.Fixtures

  alias Aponte.{Coupons, DjApplications, Editions, Merch, Repo, Tickets}
  alias Aponte.Editions.Edition
  alias Aponte.Merch.Item

  defp merch_item(org, attrs \\ %{}) do
    defaults = %{name: "Poster", price_cents: 2000, stock: 10}
    {:ok, item} = Merch.create_item(org, Map.merge(defaults, attrs))
    item
  end

  defp public_coupon(org, code) do
    {:ok, coupon} =
      Coupons.create_public_coupon(org, %{
        "code" => code,
        "discount_kind" => "percent",
        "discount_value" => "10"
      })

    coupon
  end

  defp dj_application(org, name) do
    {:ok, app} =
      DjApplications.create(org, %{
        "name" => name,
        "whatsapp" => "22999998888",
        "instagram" => "dj.#{String.downcase(name)}",
        "musical_styles" => "techno",
        "about" => "quero tocar"
      })

    app
  end

  describe "scoping leakage" do
    setup do
      org_a = org_fixture(%{name: "Org A"})
      org_b = org_fixture(%{name: "Org B"})

      ed_a = edition_fixture(%{org_id: org_a.id, status: :published})
      ed_b = edition_fixture(%{org_id: org_b.id, status: :published})
      lot_a = ticket_type_fixture(ed_a)

      {:ok, order_a} = Tickets.create_order(org_a, order_attrs(ed_a, lot_a))
      {:ok, order_b} = Tickets.create_order(org_b, order_attrs(ed_b, ticket_type_fixture(ed_b)))

      item_a = merch_item(org_a)
      _item_b = merch_item(org_b)
      coupon_a = public_coupon(org_a, "ORGA10")
      _coupon_b = public_coupon(org_b, "ORGB10")
      app_a = dj_application(org_a, "Aline")
      _app_b = dj_application(org_b, "Beto")

      {:ok,
       org_a: org_a,
       org_b: org_b,
       ed_a: ed_a,
       ed_b: ed_b,
       order_a: order_a,
       order_b: order_b,
       item_a: item_a,
       coupon_a: coupon_a,
       app_a: app_a}
    end

    test "list/current functions return only the org's own rows", ctx do
      assert [e] = Editions.list_editions(ctx.org_a.id)
      assert e.id == ctx.ed_a.id

      assert Editions.current_edition(ctx.org_a.id).id == ctx.ed_a.id
      assert Editions.current_accent(ctx.org_a.id) == ctx.ed_a.accent_color

      assert [o] = Tickets.list_recent(ctx.org_a.id, 10)
      assert o.id == ctx.order_a.id

      assert [o] = Tickets.list_pending(ctx.org_a.id)
      assert o.id == ctx.order_a.id

      assert [o] = Tickets.search_orders(ctx.org_a.id, "fulano")
      assert o.id == ctx.order_a.id

      assert [i] = Merch.list_active_items(ctx.org_a.id)
      assert i.id == ctx.item_a.id

      assert [c] = Coupons.list_coupons(ctx.org_a.id)
      assert c.id == ctx.coupon_a.id

      assert [a] = DjApplications.list(ctx.org_a.id)
      assert a.id == ctx.app_a.id
    end

    test "publish archives only same-org published editions", ctx do
      draft_a = edition_fixture(%{org_id: ctx.org_a.id, status: :draft})

      assert {:ok, _} = Editions.publish(draft_a)

      assert Repo.get!(Edition, ctx.ed_a.id).status == :past
      assert Repo.get!(Edition, draft_a.id).status == :published
      # The other org's published edition is untouched.
      assert Repo.get!(Edition, ctx.ed_b.id).status == :published
    end

    test "get_edition_in_org refuses another org's edition", ctx do
      assert {:ok, e} = Editions.get_edition_in_org(ctx.org_a.id, ctx.ed_a.id)
      assert e.id == ctx.ed_a.id
      assert {:error, :not_found} = Editions.get_edition_in_org(ctx.org_a.id, ctx.ed_b.id)
    end
  end

  describe "cross-org injection" do
    test "create_order rejects another org's merch item" do
      org_a = org_fixture()
      org_b = org_fixture()
      {edition, _lot} = edition_with_lot(%{org_id: org_a.id})
      item_b = merch_item(org_b)

      assert {:error, {:unknown_merch_item, id}} =
               Tickets.create_order(org_a, %{
                 edition_id: edition.id,
                 customer_name: "Fulano",
                 customer_instagram: "fulano",
                 items: [%{merch_item_id: item_b.id, quantity: 1}]
               })

      assert id == item_b.id
      assert Repo.aggregate(Item, :count, :id) == 1
    end

    test "create_order rejects another org's ticket_type" do
      org_a = org_fixture()
      org_b = org_fixture()
      {ed_a, _lot_a} = edition_with_lot(%{org_id: org_a.id})
      {_ed_b, lot_b} = edition_with_lot(%{org_id: org_b.id})

      assert {:error, {:unknown_ticket_type, id}} =
               Tickets.create_order(org_a, %{
                 edition_id: ed_a.id,
                 customer_name: "Fulano",
                 customer_instagram: "fulano",
                 items: [%{ticket_type_id: lot_b.id, quantity: 1}]
               })

      assert id == lot_b.id
    end

    test "create_order rejects a ticket_type from another edition of the same org" do
      org = org_fixture()
      {ed_a, _lot_a} = edition_with_lot(%{org_id: org.id})
      {_ed_b, lot_b} = edition_with_lot(%{org_id: org.id})

      assert {:error, {:unknown_ticket_type, id}} =
               Tickets.create_order(org, %{
                 edition_id: ed_a.id,
                 customer_name: "Fulano",
                 customer_instagram: "fulano",
                 items: [%{ticket_type_id: lot_b.id, quantity: 1}]
               })

      assert id == lot_b.id
    end
  end

  describe "lookup_order/3" do
    setup do
      org = org_fixture()
      {edition, lot} = edition_with_lot(%{org_id: org.id})

      {:ok, order} =
        Tickets.create_order(
          org,
          order_attrs(edition, lot, %{
            customer_instagram: nil,
            customer_phone: "(22) 99876-5432"
          })
        )

      {:ok, org: org, order: order}
    end

    test "hit returns the single order, normalizing the phone", %{org: org, order: order} do
      assert {:ok, found} = Tickets.lookup_order(org.id, "(22) 99876-5432", order.id)
      assert found.id == order.id
    end

    test "wrong org with right phone and id is not_found", %{order: order} do
      other = org_fixture()
      assert {:error, :not_found} = Tickets.lookup_order(other.id, "22998765432", order.id)
    end

    test "wrong phone is not_found", %{org: org, order: order} do
      assert {:error, :not_found} = Tickets.lookup_order(org.id, "11988887777", order.id)
    end

    test "garbage id is not_found, not a cast error", %{org: org} do
      assert {:error, :not_found} = Tickets.lookup_order(org.id, "22998765432", "not-a-uuid")
    end

    test "pasted /compra/ link is accepted, extracting the uuid", %{org: org, order: order} do
      link = "https://aponte.live/sesh/compra/#{order.id}"
      assert {:ok, found} = Tickets.lookup_order(org.id, "22998765432", link)
      assert found.id == order.id
    end

    test "a ticket's short display code resolves to its order", %{org: org, order: order} do
      {:ok, _} = Tickets.confirm_order(order.id)
      [ticket] = Repo.all(Aponte.Tickets.Ticket)

      assert {:ok, found} =
               Tickets.lookup_order(
                 org.id,
                 "22998765432",
                 Aponte.Tickets.Ticket.display_code(ticket)
               )

      assert found.id == order.id
    end

    test "a ticket code only helps with the matching phone", %{org: org, order: order} do
      {:ok, _} = Tickets.confirm_order(order.id)
      [ticket] = Repo.all(Aponte.Tickets.Ticket)

      assert {:error, :not_found} =
               Tickets.lookup_order(
                 org.id,
                 "11988887777",
                 Aponte.Tickets.Ticket.display_code(ticket)
               )
    end

    test "a ticket code from another org is not_found", %{order: order} do
      {:ok, _} = Tickets.confirm_order(order.id)
      [ticket] = Repo.all(Aponte.Tickets.Ticket)
      other = org_fixture()

      assert {:error, :not_found} =
               Tickets.lookup_order(
                 other.id,
                 "22998765432",
                 Aponte.Tickets.Ticket.display_code(ticket)
               )
    end
  end

  describe "coupons across orgs" do
    test "preview refuses another org's public code" do
      org_a = org_fixture()
      org_b = org_fixture()
      coupon = public_coupon(org_b, "ORGB10")

      assert {:error, :not_found} =
               Coupons.preview(coupon.code, %{
                 customer_instagram: "x",
                 subtotal: 1000,
                 org_id: org_a.id
               })

      assert {:ok, _, _} =
               Coupons.preview(coupon.code, %{
                 customer_instagram: "x",
                 subtotal: 1000,
                 org_id: org_b.id
               })
    end

    test "phone-only order earns no bound coupon" do
      org = org_fixture()

      {:ok, _rule} =
        Coupons.create_rule(org, %{
          name: "premia",
          min_order_cents: 100,
          discount_kind: :percent,
          discount_value: 10,
          expires_in_days: 7
        })

      {edition, lot} = edition_with_lot(%{org_id: org.id})

      {:ok, order} =
        Tickets.create_order(
          org,
          order_attrs(edition, lot, %{
            customer_instagram: nil,
            customer_phone: "22998765432"
          })
        )

      assert Coupons.earned_for_order(order.id) == []
    end
  end
end
