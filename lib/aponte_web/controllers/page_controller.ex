defmodule AponteWeb.PageController do
  use AponteWeb, :controller

  alias Aponte.{Editions, Merch, Orgs}
  alias AponteWeb.SEO

  def index(conn, _params) do
    # TODO(phase-4): org comes from assigns (LoadOrg plug)
    org =
      case Orgs.get_org_by_slug("sesh") do
        {:ok, org} -> org
        {:error, :not_found} -> nil
      end

    edition = org && Editions.current_edition(org.id)
    logo = edition && SEO.abs_url(Editions.logo_url(edition.logo_path))

    conn
    |> assign(:accent, edition && edition.accent_color)
    |> assign(
      :seo_description,
      edition && "#{edition.name} — #{edition.venue}. Ingressos abertos."
    )
    |> assign(:seo_image, logo)
    |> assign(:seo_type, "website")
    |> assign(:jsonld, SEO.music_event_jsonld(edition, logo))
    |> render(:index,
      edition: edition,
      has_merch?: org != nil and Merch.list_active_items(org.id) != [],
      page_title: edition && edition.name
    )
  end

  def sobre(conn, _params) do
    render(conn, :sobre, page_title: "Sobre")
  end

  # Notification config panel. Stateless shell — the toggle/topics reflect the
  # device's own subscription, managed client-side (assets/js/client_push.js).
  def avisos(conn, _params) do
    render(conn, :avisos, page_title: "Avisos")
  end
end
