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
    {upcoming, past} = split_editions(Editions.list_editions(org.id))
    image_url = edition && SEO.abs_url(Editions.logo_url(edition.logo_path))

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
      page_title: org.name
    )
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
