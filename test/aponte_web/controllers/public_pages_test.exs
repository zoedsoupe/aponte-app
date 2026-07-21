defmodule AponteWeb.PublicPagesTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures

  describe "Aponte home" do
    test "renders the brand and the org listing", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "Aponte"
      assert html =~ "o que tá rolando em Campos"
      assert html =~ ~s(href="/sesh")
    end

    test "/sobre renders the Aponte about page", %{conn: conn} do
      html = conn |> get(~p"/sobre") |> html_response(200)
      assert html =~ "Aponte Produtoras"
    end
  end

  describe "org pages without a published edition" do
    test "vitrine renders the teaser", %{conn: conn} do
      html = conn |> get(~p"/sesh/") |> html_response(200)
      assert html =~ "em breve"
    end

    test "/sesh/comprar redirects to the vitrine when nothing is on sale", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/sesh/comprar")) == ~p"/sesh"
    end
  end

  describe "org pages with a published edition on sale" do
    setup do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
      {edition, _lot} = edition_with_lot(%{org_id: org.id, venue: "OCA ROOTS"}, %{name: "Lote 1"})
      %{edition: edition}
    end

    test "vitrine renders the flyer", %{conn: conn, edition: edition} do
      html = conn |> get(~p"/sesh/") |> html_response(200)
      assert html =~ edition.name
      assert html =~ "OCA ROOTS"
      assert html =~ "Garantir ingresso"
    end

    test "/sesh/comprar renders the buy form with the lot", %{conn: conn} do
      html = conn |> get(~p"/sesh/comprar") |> html_response(200)
      assert html =~ "comprar"
      assert html =~ "Lote 1"
    end
  end

  test "static public pages render", %{conn: conn} do
    assert conn |> get(~p"/sesh/sobre") |> html_response(200) =~ "Avisos"
    assert conn |> get(~p"/sesh/meus-ingressos") |> html_response(200) =~ "Meus ingressos"
  end

  test "/sesh/avisos redirects to the sobre page avisos section", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/sesh/avisos")) == "/sesh/sobre#avisos"
  end

  describe "client JS seams" do
    test "sobre renders the org-scoped push endpoint data attributes", %{conn: conn} do
      html = conn |> get(~p"/sesh/sobre") |> html_response(200)
      assert html =~ ~s(data-push-vapid-url="/sesh/push/vapid-key")
      assert html =~ ~s(data-push-sub-url="/sesh/push/subscribe")
    end

    test "meus-ingressos renders the org slug for the client-side order store", %{
      conn: conn
    } do
      html = conn |> get(~p"/sesh/meus-ingressos") |> html_response(200)
      assert html =~ ~s(data-order-history data-org-slug="sesh")
      assert html =~ ~s(data-order-import data-org-slug="sesh")
    end
  end
end
