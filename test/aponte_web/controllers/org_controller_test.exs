defmodule AponteWeb.OrgControllerTest do
  use AponteWeb.ConnCase, async: false

  test "vitrine renders for an active org", %{conn: conn} do
    html = conn |> get("/sesh/") |> html_response(200)
    assert html =~ "Próxima edição em breve"
  end

  test "vitrine 404s for an unknown org", %{conn: conn} do
    assert conn |> get("/nope/") |> html_response(404)
  end
end
