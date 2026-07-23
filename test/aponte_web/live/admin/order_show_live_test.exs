defmodule AponteWeb.Admin.OrderShowLiveTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures
  import Phoenix.LiveViewTest

  alias Aponte.Tickets

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "renders an order of the scoped org", %{conn: conn, auth: auth} do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    edition = edition_fixture(%{org_id: org.id})
    order = insert_order(edition, %{customer_name: "Maria"})

    {:ok, _view, html} = conn |> authed(auth) |> live(~p"/admin/sesh/pedidos/#{order.id}")
    assert html =~ "Maria"
  end

  test "order from another org is not found (redirects)", %{conn: conn, auth: auth} do
    other = org_fixture()
    edition = edition_fixture(%{org_id: other.id})
    order = insert_order(edition)

    assert {:error, {:redirect, %{to: "/admin/sesh/buscar"}}} =
             conn |> authed(auth) |> live(~p"/admin/sesh/pedidos/#{order.id}")
  end

  test "phone-only order shows WhatsApp deep-link and the number, no DM or bare @", %{
    conn: conn,
    auth: auth
  } do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    edition = edition_fixture(%{org_id: org.id})

    order =
      insert_order(edition, %{
        customer_name: "Sem Insta",
        customer_instagram: nil,
        customer_phone: "22998765432"
      })

    {:ok, _view, html} = conn |> authed(auth) |> live(~p"/admin/sesh/pedidos/#{order.id}")

    assert html =~ "Abrir WhatsApp"
    assert html =~ "https://wa.me/5522998765432"
    assert html =~ "22998765432"
    refute html =~ "Abrir DM"
    refute html =~ "Ver perfil"
  end

  test "confirm is two-tap: first arms, second confirms", %{conn: conn, auth: auth} do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    {edition, lot} = edition_with_lot(%{org_id: org.id})
    {:ok, order} = Tickets.create_order(org, order_attrs(edition, lot))

    {:ok, view, html} = conn |> authed(auth) |> live(~p"/admin/sesh/pedidos/#{order.id}")
    assert html =~ "Confirmar pagamento"
    refute html =~ "Tocar de novo"

    html = view |> element("button", "Confirmar pagamento") |> render_click()
    assert html =~ "Tocar de novo pra confirmar R$ 10,00 · 1 ingressos"
    assert Tickets.get_order!(order.id).status == :pending

    html = view |> element("button", "Tocar de novo") |> render_click()
    assert html =~ "Pagamento confirmado"
    assert Tickets.get_order!(order.id).status == :confirmed
  end
end
