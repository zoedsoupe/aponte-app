defmodule AponteWeb.DjControllerTest do
  use AponteWeb.ConnCase, async: false

  alias Aponte.DjApplications
  alias Aponte.Settings

  test "POST /:slug/tocar when closed redirects to ?ok=1 and persists nothing", %{conn: conn} do
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
    assert redirected_to(conn) == "/#{org.slug}/tocar?ok=1"
    assert DjApplications.list(org.id) == []
  end
end
