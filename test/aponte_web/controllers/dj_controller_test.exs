defmodule AponteWeb.DjControllerTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures

  alias Aponte.DjApplications
  alias Aponte.Settings

  test "GET /sesh/tocar redirects to the sobre page tocar section", %{conn: conn} do
    assert redirected_to(get(conn, "/sesh/tocar")) == "/sesh/sobre#tocar"
  end

  test "GET /:slug/tocar 404s for orgs without the bespoke section", %{conn: conn} do
    org_fixture(%{slug: "arena", name: "Arena"})

    html = conn |> get("/arena/tocar") |> html_response(404)
    # org-scoped 404: back link points at the org vitrine, not the Aponte home
    assert html =~ "Voltar pra Arena"
    assert html =~ ~s(href="/arena")
  end

  test "failed submit re-renders the sobre form preserving input, focusing the first invalid field",
       %{conn: conn} do
    {:ok, _} = Settings.set_dj_applications_open(true)

    ts = Phoenix.Token.sign(AponteWeb.Endpoint, "dj_form", System.system_time(:second) - 10)

    params = %{
      "ts" => ts,
      "dj_application" => %{
        "name" => "",
        "whatsapp" => "22999998888",
        "instagram" => "fulanodj",
        "musical_styles" => "techno",
        "about" => "quero tocar"
      }
    }

    html = conn |> post("/sesh/tocar", params) |> html_response(200)

    assert html =~ "Confere os campos e tenta de novo."
    # input preserved
    assert html =~ ~s(value="22999998888")
    # exactly one invalid field (name) gets autofocus
    assert html =~ "autofocus"
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
