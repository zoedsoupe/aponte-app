defmodule AponteWeb.Admin.ProductFormLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aponte.Merch

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "price accepts reais with comma and saves as cents", %{conn: conn, auth: auth} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/produtos/novo")

    # validate mostra o parse ("= R$ 35,00") e mantém o raw no input
    html =
      view
      |> form("#product-form", %{item: %{name: "Camiseta", price_cents: "35,00"}})
      |> render_change()

    assert html =~ "= R$ 35,00"
    assert html =~ ~s(value="35,00")

    assert {:error, {:live_redirect, %{to: "/admin/sesh"}}} =
             view
             |> form("#product-form", %{
               item: %{name: "Camiseta", kind: "online", price_cents: "35,00", stock: "5"}
             })
             |> render_submit()

    assert [item] = Merch.list_items(org_id())
    assert item.name == "Camiseta"
    assert item.price_cents == 3500
  end

  test "price accepts plain integer reais and dot decimals", %{conn: conn, auth: auth} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/produtos/novo")

    html =
      view
      |> form("#product-form", %{item: %{name: "Água", price_cents: "35"}})
      |> render_change()

    assert html =~ "= R$ 35,00"

    html =
      view
      |> form("#product-form", %{item: %{name: "Água", price_cents: "2.50"}})
      |> render_change()

    assert html =~ "= R$ 2,50"
  end

  defp org_id do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    org.id
  end
end
