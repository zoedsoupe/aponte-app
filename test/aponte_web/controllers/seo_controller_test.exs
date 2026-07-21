defmodule AponteWeb.SeoControllerTest do
  use AponteWeb.ConnCase, async: false

  test "sitemap lists org-scoped URLs for active orgs", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    assert body =~ "/sesh/loja"
    assert body =~ "/sesh/comprar"
    assert body =~ "/sesh/avisos"
    assert body =~ "/sesh/tocar"
    assert body =~ "/sobre"
  end

  test "sitemap does not list the dead global paths", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    refute body =~ ~r{<loc>https?://[^/<]+/loja</loc>}
    refute body =~ ~r{<loc>https?://[^/<]+/tocar</loc>}
  end

  test "robots disallows the org-scoped purchase paths", %{conn: conn} do
    body = conn |> get(~p"/robots.txt") |> response(200)

    assert body =~ "Disallow: /admin"
    assert body =~ "Disallow: /*/compra"
    assert body =~ "Disallow: /*/meus-ingressos"
  end
end
