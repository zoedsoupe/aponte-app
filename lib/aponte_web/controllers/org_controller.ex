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
    images = Orgs.list_images(org.id)
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
      images: images,
      upcoming_editions: upcoming,
      past_editions: past,
      page_title: org.name
    )
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
