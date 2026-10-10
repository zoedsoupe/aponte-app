defmodule AponteWeb.Admin.DashboardLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Aponte.Fixtures

  alias Aponte.Tickets
  alias Aponte.Tickets.Order

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "confirms a pending order inline with two taps", %{conn: conn, auth: auth} do
    org = org_fixture()
    {edition, lot} = edition_with_lot(%{org_id: org.id}, %{capacity: 3})

    {:ok, order} =
      Tickets.create_order(org, order_attrs(edition, lot, %{customer_name: "Maria"}))

    {:ok, view, html} = conn |> authed(auth) |> live(~p"/admin/#{org.slug}")

    assert html =~ "Pendentes (1)"
    assert html =~ "Confirmar pagamento"

    selector = "button[phx-value-id='#{order.id}']"

    # first tap arms the order
    view |> element(selector) |> render_click()
    assert render(view) =~ "Tocar de novo"

    # second tap confirms
    view |> element(selector) |> render_click()
    assert render(view) =~ "Pagamento confirmado"
    assert Aponte.Repo.get!(Order, order.id).status == :confirmed
  end
end
