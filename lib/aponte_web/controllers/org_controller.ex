defmodule AponteWeb.OrgController do
  @moduledoc """
  Org vitrine (`/:org_slug`): current published edition flyer, gallery thumb
  grid, about text and social links. The org is loaded by Plugs.LoadOrg.
  """

  use AponteWeb, :controller

  alias Aponte.{Editions, Orgs}
  alias AponteWeb.SEO

  def show(conn, _params) do
    org = conn.assigns.org
    edition = Editions.current_edition(org.id)
    images = Orgs.list_images(org.id)

    conn
    |> assign(:seo_description, seo_description(org))
    |> assign(:seo_type, "website")
    |> assign(:seo_image, edition && SEO.abs_url(Editions.logo_url(edition.logo_path)))
    |> render(:show,
      org: org,
      edition: edition,
      images: images,
      page_title: org.name
    )
  end

  # SEO description from the org's about, truncated to a snippet.
  defp seo_description(%{about: about}) when is_binary(about) and about != "" do
    about |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)
  end

  defp seo_description(%{name: name}), do: "#{name} - eventos e ingressos."
end
