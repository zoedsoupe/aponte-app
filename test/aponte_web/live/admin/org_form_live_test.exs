defmodule AponteWeb.Admin.OrgFormLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aponte.{Orgs, Uploads}

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  describe "new (/admin/organizacoes/nova)" do
    test "creates an org with social links", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/organizacoes/nova")

      # Rows only accept params once they exist in the DOM.
      view |> element("button", "+ Adicionar link") |> render_click()
      view |> element("button", "+ Adicionar link") |> render_click()

      assert {:error, {:live_redirect, %{to: "/admin/arena"}}} =
               view
               |> form("#org-form",
                 org: %{
                   name: "A Arena",
                   slug: "arena",
                   about: "rolê em campos",
                   instagram: "a.arena",
                   pix_key: "arena@pix",
                   social_links: %{
                     "0" => %{"label" => "site", "url" => "https://arena.example"},
                     "1" => %{"label" => "", "url" => ""}
                   }
                 }
               )
               |> render_submit()

      assert {:ok, org} = Orgs.get_org_by_slug("arena")
      assert org.name == "A Arena"
      assert org.instagram == "a.arena"
      assert org.pix_key == "arena@pix"
      # Fully-empty rows are dropped before the changeset.
      assert org.social_links == [%{"label" => "site", "url" => "https://arena.example"}]
    end

    test "invalid slug stays on the form with an error", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/organizacoes/nova")

      html =
        view
        |> form("#org-form", org: %{name: "A Arena", slug: "Admin"})
        |> render_submit()

      assert html =~ "reservado"
      assert {:error, :not_found} = Orgs.get_org_by_slug("admin")
    end

    test "social_links rows without url fail validation", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/organizacoes/nova")

      view |> element("button", "+ Adicionar link") |> render_click()

      html =
        view
        |> form("#org-form",
          org: %{
            name: "A Arena",
            slug: "arena",
            social_links: %{"0" => %{"label" => "site", "url" => ""}}
          }
        )
        |> render_submit()

      assert html =~ "label e url"
      assert {:error, :not_found} = Orgs.get_org_by_slug("arena")
    end

    test "logo upload stores a content-hashed webp and sets logo_path", %{
      conn: conn,
      auth: auth
    } do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/organizacoes/nova")

      logo =
        file_input(view, "#org-form", :logo, [
          %{name: "logo.png", content: "fake png bytes", type: "image/png"}
        ])

      render_upload(logo, "logo.png")

      assert {:error, {:live_redirect, %{to: "/admin/arena"}}} =
               view
               |> form("#org-form", org: %{name: "A Arena", slug: "arena"})
               |> render_submit()

      assert {:ok, org} = Orgs.get_org_by_slug("arena")
      assert org.logo_path =~ ~r/^[0-9a-f]{64}\.webp$/
      assert File.exists?(Path.join(Uploads.org_dir(org.id), org.logo_path))
    end

    test "svg logo is stored raw (no vips)", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/organizacoes/nova")

      svg = ~s|<svg xmlns="http://www.w3.org/2000/svg"></svg>|

      logo =
        file_input(view, "#org-form", :logo, [
          %{name: "logo.svg", content: svg, size: byte_size(svg), type: "image/svg+xml"}
        ])

      render_upload(logo, "logo.svg")

      assert {:error, {:live_redirect, %{to: "/admin/arena"}}} =
               view
               |> form("#org-form", org: %{name: "A Arena", slug: "arena"})
               |> render_submit()

      assert {:ok, org} = Orgs.get_org_by_slug("arena")
      assert org.logo_path =~ ~r/\.svg$/
      assert File.read!(Path.join(Uploads.org_dir(org.id), org.logo_path)) == svg
    end
  end

  describe "edit (/admin/:org_slug/perfil)" do
    test "updates the org and keeps the slug immutable", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/perfil")

      # The slug field is not rendered at all on edit (immutable, no noise).
      refute has_element?(view, ~s|input[name="org[slug]"]|)

      html =
        view
        |> form("#org-form", org: %{name: "SESH", pix_key: "nova-chave@pix"})
        |> render_submit()

      assert html =~ "Perfil salvo"
      assert {:ok, org} = Orgs.get_org_by_slug("sesh")
      assert org.pix_key == "nova-chave@pix"
    end

    test "rejects a PIX copia-e-cola pasted as the key", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/perfil")

      emv =
        "00020126360014br.gov.bcb.pix01145306658900019752040000530398654040.005802" <>
          "BR5908SESH LAB6006CAMPOS62070503***63042EE0"

      {:ok, before} = Orgs.get_org_by_slug("sesh")

      html =
        view
        |> form("#org-form", org: %{name: "SESH", pix_key: emv})
        |> render_submit()

      assert html =~ "copia-e-cola"
      assert {:ok, org} = Orgs.get_org_by_slug("sesh")
      assert org.pix_key == before.pix_key
    end

    test "persists theme colors", %{conn: conn, auth: auth} do
      {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/perfil")

      view
      |> form("#org-form",
        org: %{name: "SESH", accent_color: "#F07BC0", bg_color: "#05070A", fg_color: "#F3F3F3"}
      )
      |> render_submit()

      assert {:ok, org} = Orgs.get_org_by_slug("sesh")
      assert org.bg_color == "#05070A"
      assert org.fg_color == "#F3F3F3"
    end
  end
end
