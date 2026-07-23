defmodule AponteWeb.Admin.ScannerLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Aponte.Fixtures

  alias Aponte.{Repo, Tickets}
  alias Aponte.Tickets.Ticket

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")

    # Admin routes are org-scoped; the "sesh" org is seeded by the orgs migration.
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    {edition, lot} = edition_with_lot(%{org_id: org.id})
    {:ok, order} = Tickets.create_order(org, order_attrs(edition, lot))
    {:ok, _} = Tickets.confirm_order(order.id)
    [ticket] = Repo.all(Ticket)

    %{auth: auth, edition: edition, ticket: ticket}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "requires basic auth", %{conn: conn} do
    assert get(conn, ~p"/admin/sesh/validar").status == 401
  end

  test "shows the door header for the published edition", %{conn: conn, auth: auth} do
    {:ok, _view, html} = conn |> authed(auth) |> live(~p"/admin/sesh/validar")
    assert html =~ "Porta"
    assert html =~ "validadas 0 / vendidas 1"
  end

  test "first scan is green, rescan is red (já validado)", %{conn: conn, auth: auth, ticket: t} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/validar")

    html = view |> element("#scanner") |> render_hook("scan", %{"code" => t.code})
    assert html =~ "scan-result--ok"
    assert html =~ "Entrou"
    assert html =~ "validadas 1 / vendidas 1"

    html = view |> element("#scanner") |> render_hook("scan", %{"code" => t.code})
    assert html =~ "scan-result--err"
    assert html =~ "Já validado"
  end

  test "manual unknown code is not found", %{conn: conn, auth: auth} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/validar")

    html = view |> form("#manual-code-form", %{code: "ZZZZZZZZ"}) |> render_submit()
    assert html =~ "scan-result--err"
    assert html =~ "Não encontrado"
  end

  test "manual validate accepts a noisy lowercase/hyphenated code", %{
    conn: conn,
    auth: auth,
    ticket: t
  } do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/validar")

    noisy = String.downcase(String.slice(t.code, 0, 4) <> "-" <> String.slice(t.code, 4, 4))
    html = view |> form("#manual-code-form", %{code: noisy}) |> render_submit()
    assert html =~ "scan-result--ok"
  end

  test "name search lists confirmed buyers and Validar checks them in", %{
    conn: conn,
    auth: auth
  } do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/validar")

    html = view |> element("#name-search-form") |> render_change(%{"name" => "fulano"})
    assert html =~ "Fulano"
    assert html =~ "Validar"

    html = view |> element(".door-match button", "Validar") |> render_click()
    assert html =~ "scan-result--ok"
    assert html =~ "validadas 1 / vendidas 1"
    # validated ticket drops out of the name results
    refute html =~ "door-match-name"
  end

  test "name search with no match says so", %{conn: conn, auth: auth} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/validar")

    html = view |> element("#name-search-form") |> render_change(%{"name" => "ninguém"})
    assert html =~ "Nenhum ingresso confirmado com esse nome."
  end
end
