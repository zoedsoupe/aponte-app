defmodule AponteWeb.OrgControllerTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures

  test "vitrine renders for an active org", %{conn: conn} do
    html = conn |> get("/sesh/") |> html_response(200)
    assert html =~ "Próxima edição em breve"
  end

  test "vitrine 404s for an unknown org", %{conn: conn} do
    assert conn |> get("/nope/") |> html_response(404)
  end

  test "pages emit the theme as inline CSS vars (org accent, platform bg/ink)", %{conn: conn} do
    html = conn |> get("/sesh/") |> html_response(200)
    assert html =~ "--bg: #FEF8DA"
    assert html =~ "--ink: #49422F"
    assert html =~ "--accent: #F07BC0"
  end

  test "custom org bg/fg override the platform defaults", %{conn: conn} do
    org_fixture(%{slug: "darko", bg_color: "#05070A", fg_color: "#F3F3F3"})

    html = conn |> get("/darko/") |> html_response(200)
    assert html =~ "--bg: #05070A"
    assert html =~ "--ink: #F3F3F3"
  end
end
