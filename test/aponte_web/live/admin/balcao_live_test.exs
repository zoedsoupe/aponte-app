defmodule AponteWeb.Admin.BalcaoLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Aponte.Fixtures

  alias Aponte.{Bar, Merch}

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "cash asks for confirmation before recording the sale", %{conn: conn, auth: auth} do
    org = org_fixture()
    {edition, _lot} = edition_with_lot(%{org_id: org.id})

    {:ok, _item} =
      Merch.create_item(org, %{name: "Cerveja", price_cents: 1000, stock: 5, kind: :counter})

    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/#{org.slug}/balcao")

    # add to cart, tap Dinheiro
    view |> element(".pos-item-tap") |> render_click()
    view |> element("button", "Dinheiro") |> render_click()

    # confirm sheet shows, but nothing recorded yet
    assert render(view) =~ "em dinheiro?"
    assert Bar.stats(edition.id).count == 0

    # confirm records the sale
    view |> element("button", "Recebido") |> render_click()
    assert Bar.stats(edition.id).count == 1
  end

  test "cancelling the cash sheet records nothing", %{conn: conn, auth: auth} do
    org = org_fixture()
    {edition, _lot} = edition_with_lot(%{org_id: org.id})

    {:ok, _item} =
      Merch.create_item(org, %{name: "Cerveja", price_cents: 1000, stock: 5, kind: :counter})

    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/#{org.slug}/balcao")

    view |> element(".pos-item-tap") |> render_click()
    view |> element("button", "Dinheiro") |> render_click()
    view |> element("button", "cancelar") |> render_click()

    assert Bar.stats(edition.id).count == 0
  end
end
