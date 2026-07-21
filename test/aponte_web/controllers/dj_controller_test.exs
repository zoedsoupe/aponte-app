defmodule AponteWeb.DjControllerTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures

  alias Aponte.DjApplications
  alias Aponte.Settings

  test "GET /sesh/tocar redirects to the sobre page tocar section", %{conn: conn} do
    assert redirected_to(get(conn, "/sesh/tocar")) == "/sesh/sobre#tocar"
  end

  test "GET /:slug/tocar 404s for orgs without the bespoke section", %{conn: conn} do
    org_fixture(%{slug: "arena"})
    assert conn |> get("/arena/tocar") |> html_response(404)
  end

  test "sobre renders the tocar form only for sesh", %{conn: conn} do
    # The flag is a persisted row — pin it open so this test doesn't depend on
    # execution order relative to the "when closed" test.
    {:ok, _} = Settings.set_dj_applications_open(true)
    org_fixture(%{slug: "arena"})

    html = conn |> get("/sesh/sobre") |> html_response(200)
    assert html =~ ~s(id="tocar")
    assert html =~ "Quer tocar?"
    assert html =~ ~s(action="/sesh/tocar")

    refute conn |> get("/arena/sobre") |> html_response(200) =~ ~s(id="tocar")
  end

  test "POST /:slug/tocar when closed redirects to sobre?ok=1 and persists nothing", %{
    conn: conn
  } do
    {:ok, _} = Settings.set_dj_applications_open(false)
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")

    params = %{
      "dj_application" => %{
        "name" => "DJ Fulano",
        "whatsapp" => "22999998888",
        "instagram" => "fulanodj",
        "musical_styles" => "techno",
        "about" => "quero tocar"
      }
    }

    conn = post(conn, "/#{org.slug}/tocar", params)
    assert redirected_to(conn) == "/#{org.slug}/sobre?ok=1#tocar"
    assert DjApplications.list(org.id) == []
  end
end
