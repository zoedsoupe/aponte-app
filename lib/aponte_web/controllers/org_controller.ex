defmodule AponteWeb.OrgController do
  @moduledoc """
  Org vitrine (`/:org_slug`): current published edition flyer, gallery thumb
  grid, about text and social links. The org is loaded by Plugs.LoadOrg.
  """

  use AponteWeb, :controller

  alias Aponte.{Clock, Editions, Orgs}
  alias AponteWeb.SEO

  def show(conn, _params) do
    org = conn.assigns.org
    edition = Editions.current_edition(org.id)
    {upcoming, past} = split_editions(Editions.list_public_editions(org.id))
    image_url = edition && SEO.abs_url(Editions.logo_url(edition.logo_path))
    # Empty vitrine only: a row of gallery thumbs teasing /galeria.
    gallery_tease = if edition, do: [], else: Orgs.list_images(org.id) |> Enum.take(4)

    conn
    |> assign(:seo_description, seo_description(org))
    |> assign(:seo_type, "website")
    |> assign(:seo_image, image_url)
    |> assign(:jsonld, SEO.music_event_jsonld(edition, image_url, org.name))
    |> render(:show,
      org: org,
      edition: edition,
      upcoming_editions: upcoming,
      past_editions: past,
      gallery_tease: gallery_tease,
      page_title: org.name
    )
  end

  @doc """
  Per-org PWA manifest: the installed app is the org's, not Aponte's. Name,
  colors, start_url/scope and icon all come from the org; org-less pages keep
  the static Aponte manifest. Without an uploaded logo the icon is a letter
  tile (org initial on the org accent, inline SVG).
  """
  def manifest(conn, _params) do
    org = conn.assigns.org
    bg = org_color(org, :bg_color, "#FAF5EC")

    conn
    |> put_resp_content_type("application/manifest+json")
    |> json(%{
      name: org.name,
      short_name: org.name,
      lang: "pt-br",
      start_url: "/#{org.slug}",
      scope: "/#{org.slug}",
      display: "standalone",
      orientation: "portrait",
      background_color: bg,
      theme_color: bg,
      icons: [manifest_icon(org)]
    })
  end

  def about(conn, params) do
    org = conn.assigns.org

    conn
    |> assign(:seo_description, seo_description(org))
    |> render(
      :about,
      [org: org, page_title: "Sobre - #{org.name}"] ++ dj_assigns(conn, org, params)
    )
  end

  def gallery(conn, _params) do
    org = conn.assigns.org

    render(conn, :gallery,
      org: org,
      images: Orgs.list_images(org.id),
      page_title: "Galeria - #{org.name}"
    )
  end

  # The DJ application section on the sobre page is bespoke to SESH
  # (custom-pages model): only that org gets the form assigns; every other
  # org's sobre page renders without them.
  defp dj_assigns(conn, %{slug: "sesh"}, params) do
    [
      dj_changeset: Aponte.DjApplications.change(%Aponte.DjApplications.DjApplication{}),
      dj_submitted: params["ok"] == "1",
      dj_form_ts: AponteWeb.DjController.sign_form_ts(conn),
      dj_open?: Aponte.Settings.dj_applications_open?()
    ]
  end

  defp dj_assigns(_conn, _org, _params), do: []

  defp manifest_icon(%{logo_path: path} = org) when is_binary(path) and path != "" do
    src = "/uploads/orgs/#{org.id}/#{path}"
    %{src: src, type: MIME.from_path(src), sizes: "any", purpose: "any"}
  end

  defp manifest_icon(org) do
    letter = org.name |> String.first() |> String.upcase()
    tile = org_color(org, :accent_color, "#BF7262")
    fg = org_color(org, :bg_color, "#FAF5EC")

    svg =
      ~s|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="96" fill="#{tile}"/><text x="50%" y="50%" dy="0.36em" text-anchor="middle" font-family="sans-serif" font-weight="700" font-size="280" fill="#{fg}">#{letter}</text></svg>|

    %{
      src: "data:image/svg+xml," <> URI.encode(svg),
      type: "image/svg+xml",
      sizes: "any",
      purpose: "any"
    }
  end

  defp org_color(org, field, fallback) do
    case Map.get(org, field) do
      color when is_binary(color) and color != "" -> color
      _ -> fallback
    end
  end

  # Upcoming (starts_at >= now, soonest first) vs past (most recent first).
  defp split_editions(editions) do
    now = Clock.now_utc()

    {upcoming, past} =
      Enum.split_with(editions, &(DateTime.compare(&1.starts_at, now) != :lt))

    {Enum.sort_by(upcoming, & &1.starts_at, {:asc, DateTime}),
     Enum.sort_by(past, & &1.starts_at, {:desc, DateTime})}
  end

  # SEO description from the org's about, truncated to a snippet.
  defp seo_description(%{about: about}) when is_binary(about) and about != "" do
    about |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)
  end

  defp seo_description(%{name: name}), do: "#{name} - eventos e ingressos."
end
