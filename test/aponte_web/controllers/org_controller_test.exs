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
    assert html =~ "--bg: #FAF5EC"
    assert html =~ "--ink: #49422F"
    assert html =~ "--accent: #F07BC0"
    assert html =~ "color-scheme: light"
    assert html =~ ~s(name="theme-color" content="#FAF5EC")
  end

  test "custom org bg/fg override the platform defaults", %{conn: conn} do
    org_fixture(%{slug: "darko", bg_color: "#05070A", fg_color: "#F3F3F3"})

    html = conn |> get("/darko/") |> html_response(200)
    assert html =~ "--bg: #05070A"
    assert html =~ "--ink: #F3F3F3"
    assert html =~ "color-scheme: dark"
    assert html =~ ~s(name="theme-color" content="#05070A")
  end

  describe "org chrome" do
    test "org pages carry zero Aponte branding", %{conn: conn} do
      for path <- ["/sesh/", "/sesh/sobre", "/sesh/galeria"] do
        html = conn |> get(path) |> html_response(200)
        refute html =~ "aponte-logo", "#{path} leaks the Aponte logo"
        refute html =~ "hand-print", "#{path} leaks the Aponte hand motif"
      end
    end

    test "tab bar has the org section tabs, Sobre trailing", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)

      assert html =~ ~s(class="tab-bar")
      assert html =~ ~s(aria-label="Navegação, SESH")

      for href <- ["/sesh", "/sesh/loja", "/sesh/meus-ingressos", "/sesh/sobre"] do
        assert html =~ ~s(href="#{href}"), "tab bar missing #{href}"
      end

      assert html =~ "Pedidos"
      assert html =~ "tab-bar-wordmark"
    end

    test "Galeria tab hides when the org has no gallery images", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)
      refute html =~ ~s(href="/sesh/galeria")
    end

    test "Galeria tab shows when the org has gallery images", %{conn: conn} do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")

      {:ok, _img} =
        Aponte.Orgs.add_image(org, %{
          path: "web/abc.webp",
          thumb_path: "thumbs/abc.webp",
          content_hash: "abc",
          byte_size: 1234
        })

      html = conn |> get("/sesh/") |> html_response(200)
      assert html =~ ~s(href="/sesh/galeria")
    end

    test "org pages have no top navbar; the Aponte brand pages drop it too", %{conn: conn} do
      for path <- ["/sesh/", "/sesh/sobre", "/sesh/galeria", "/sesh/loja", "/sesh/meus-ingressos"] do
        refute conn |> get(path) |> html_response(200) =~ "site-header",
               "#{path} must not render the site header"
      end

      # the shell hero carries the brand; the nav is redundant with the page actions
      refute conn |> get("/") |> html_response(200) =~ "site-header"
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

    test "empty about copy names the org", %{conn: conn} do
      org_fixture(%{slug: "arena", name: "Arena"})

      html = conn |> get("/arena/sobre") |> html_response(200)
      assert html =~ "Arena ainda não escreveu sobre si."
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
          status: :published,
          starts_at: DateTime.add(DateTime.utc_now(), 30 * 86_400) |> DateTime.truncate(:second)
        })

      draft =
        edition_fixture(%{
          org_id: org.id,
          name: "SESH RASCUNHO",
          status: :draft,
          starts_at: DateTime.add(DateTime.utc_now(), 60 * 86_400) |> DateTime.truncate(:second)
        })

      %{org: org, past: past, upcoming: upcoming, draft: draft}
    end

    test "vitrine renders upcoming and past sections", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)

      assert html =~ "Próximas edições"
      assert html =~ "Edições passadas"
      assert html =~ "SESH DO FUTURO"
      assert html =~ "SESH DO PASSADO"
    end

    test "draft editions never leak to the vitrine", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)
      refute html =~ "SESH RASCUNHO"
    end

    test "only the current edition links to the compra flow", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)

      assert html =~ ~s(href="/sesh/comprar")
      # the past row is plain text (no per-edition public pages in v1)
      assert html =~ ~s(<span class="text-base text-dim">SESH DO PASSADO</span>)
    end
  end

  describe "org identity artwork" do
    test "SESH keeps its own vector when no art is uploaded", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)
      assert html =~ "sesh-logo"
      refute html =~ "org-wordmark"
    end

    test "other orgs fall back to the name wordmark, never the SESH vector", %{conn: conn} do
      org_fixture(%{slug: "arena", name: "Arena"})

      html = conn |> get("/arena/") |> html_response(200)
      assert html =~ "org-wordmark"
      assert html =~ "Arena"
      refute html =~ "sesh-logo"
    end

    test "uploaded org logo renders with the org name as alt", %{conn: conn} do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
      {:ok, _org} = Aponte.Orgs.update_org(org, %{logo_path: "web/logo.webp"})

      html = conn |> get("/sesh/") |> html_response(200)
      assert html =~ ~s(alt="SESH")
      refute html =~ ~s(alt="SESH LAB.")
    end
  end

  describe "empty vitrine" do
    test "teases the gallery and instagram; the avisos CTA stays primary", %{conn: conn} do
      {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
      {:ok, org} = Aponte.Orgs.update_org(org, %{instagram: "coletivo.sesh"})

      {:ok, _img} =
        Aponte.Orgs.add_image(org, %{
          path: "web/abc.webp",
          thumb_path: "thumbs/abc.webp",
          content_hash: "abc",
          byte_size: 1234
        })

      html = conn |> get("/sesh/") |> html_response(200)
      assert html =~ "vitrine-gallery-tease"
      assert html =~ "/uploads/orgs/#{org.id}/thumbs/abc.webp"
      assert html =~ "@coletivo.sesh"
      assert html =~ "Quero receber avisos"
    end

    test "no tease row without gallery images", %{conn: conn} do
      html = conn |> get("/sesh/") |> html_response(200)
      refute html =~ "vitrine-gallery-tease"
      assert html =~ "Quero receber avisos"
    end
  end

  describe "web app manifest" do
    test "serves a per-org manifest with org name, colors and scope", %{conn: conn} do
      conn = get(conn, "/sesh/manifest.webmanifest")

      assert %{
               "name" => "SESH",
               "start_url" => "/sesh",
               "scope" => "/sesh",
               "theme_color" => "#FAF5EC",
               "background_color" => "#FAF5EC",
               "icons" => [%{"src" => "data:image/svg+xml," <> _rest}]
             } = json_response(conn, 200)
    end

    test "org pages link the per-org manifest; the shell keeps the static one", %{conn: conn} do
      assert conn |> get("/sesh/") |> html_response(200) =~ ~s(href="/sesh/manifest.webmanifest")

      html = conn |> get("/") |> html_response(200)
      assert html =~ ~s(href="/manifest.webmanifest")
      refute html =~ ~s(href="/sesh/manifest.webmanifest")
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
