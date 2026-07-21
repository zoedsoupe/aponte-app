defmodule AponteWeb.Admin.OrderShowLiveTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures
  import Phoenix.LiveViewTest

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
end
