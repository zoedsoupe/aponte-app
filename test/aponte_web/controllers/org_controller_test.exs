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
    assert html =~ "color-scheme: light"
  end

  test "custom org bg/fg override the platform defaults", %{conn: conn} do
    org_fixture(%{slug: "darko", bg_color: "#05070A", fg_color: "#F3F3F3"})

    html = conn |> get("/darko/") |> html_response(200)
    assert html =~ "--bg: #05070A"
    assert html =~ "--ink: #F3F3F3"
    assert html =~ "color-scheme: dark"
  end

  describe "org chrome" do
    test "org pages carry zero Aponte branding", %{conn: conn} do
      for path <- ["/sesh/", "/sesh/sobre", "/sesh/galeria"] do
        html = conn |> get(path) |> html_response(200)
        refute html =~ "aponte-logo", "#{path} leaks the Aponte logo"
        refute html =~ "hand-print", "#{path} leaks the Aponte hand motif"
      end
    end

    test "tab bar has 5 tabs with the org section hrefs", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)

      assert html =~ ~s(class="tab-bar")

      for href <- ["/sesh", "/sesh/sobre", "/sesh/galeria", "/sesh/loja", "/sesh/meus-ingressos"] do
        assert html =~ ~s(href="#{href}"), "tab bar missing #{href}"
      end
    end

    test "org pages have no top navbar; the Aponte shell keeps its own", %{conn: conn} do
      for path <- ["/sesh/", "/sesh/sobre", "/sesh/galeria", "/sesh/loja", "/sesh/meus-ingressos"] do
        refute conn |> get(path) |> html_response(200) =~ "site-header",
               "#{path} must not render the site header"
      end

      assert conn |> get("/") |> html_response(200) =~ "site-header"
    end
  end

  describe "sobre page" do
    setup do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")

      {:ok, org} =
        Aponte.Orgs.update_org(org, %{
          about: "Coletivo de Campos dos Goytacazes.\n\nFesta comunitária.",
          instagram: "coletivo.sesh",
          social_links: [%{"label" => "YouTube", "url" => "https://youtube.com/@sesh"}]
        })

      %{org: org}
    end

    test "renders the about text, handle and social links", %{conn: conn} do
      html = conn |> get("/sesh/sobre") |> html_response(200)

      assert html =~ "Coletivo de Campos dos Goytacazes."
      assert html =~ "Festa comunitária."
      assert html =~ "@coletivo.sesh"
      assert html =~ "YouTube"
    end

    test "renders the avisos section with the org-scoped push endpoints", %{conn: conn} do
      html = conn |> get("/sesh/sobre") |> html_response(200)

      assert html =~ ~s(id="avisos")
      assert html =~ "Ativar avisos"
      assert html =~ ~s(data-push-vapid-url="/sesh/push/vapid-key")
      assert html =~ ~s(data-push-sub-url="/sesh/push/subscribe")
    end

    test "/avisos redirects to the sobre anchor", %{conn: conn} do
      assert redirected_to(get(conn, "/sesh/avisos")) == "/sesh/sobre#avisos"
    end
  end

  describe "galeria page" do
    test "renders the empty state without images", %{conn: conn} do
      html = conn |> get("/sesh/galeria") |> html_response(200)
      assert html =~ "Galeria"
      assert html =~ "Nenhuma foto por aqui ainda."
    end

    test "renders the image grid", %{conn: conn} do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")

      {:ok, _img} =
        Aponte.Orgs.add_image(org, %{
          path: "web/abc.webp",
          thumb_path: "thumbs/abc.webp",
          content_hash: "abc",
          byte_size: 1234
        })

      html = conn |> get("/sesh/galeria") |> html_response(200)
      assert html =~ "gallery-page-grid"
      assert html =~ "/uploads/orgs/#{org.id}/thumbs/abc.webp"
    end
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
