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

  describe "editions list" do
    setup do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")

      past =
        edition_fixture(%{
          org_id: org.id,
          name: "SESH DO PASSADO",
          status: :past,
          starts_at: DateTime.add(DateTime.utc_now(), -30 * 86_400) |> DateTime.truncate(:second)
        })

      upcoming =
        edition_fixture(%{
          org_id: org.id,
          name: "SESH DO FUTURO",
          status: :draft,
          starts_at: DateTime.add(DateTime.utc_now(), 30 * 86_400) |> DateTime.truncate(:second)
        })

      %{org: org, past: past, upcoming: upcoming}
    end

    test "vitrine renders upcoming and past sections", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)

      assert html =~ "Próximas edições"
      assert html =~ "Edições passadas"
      assert html =~ "SESH DO FUTURO"
      assert html =~ "SESH DO PASSADO"
    end

    test "non-current rows are plain text (no compra link)", %{conn: conn} do
      # Setup has only draft/past editions — nothing published, no flyer — so
      # any /comprar link could only come from the editions list.
      html = conn |> get("/sesh/") |> html_response(200)

      refute html =~ ~s(href="/sesh/comprar")
    end
  end

  test "vitrine emits MusicEvent JSON-LD with the org as organizer", %{conn: conn} do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    edition_fixture(%{org_id: org.id, name: "SESH JSONLD", status: :published})

    html = conn |> get("/sesh/") |> html_response(200)
    assert html =~ "application/ld+json"
    assert html =~ "MusicEvent"
    assert html =~ ~s("name":"SESH")
  end
end
