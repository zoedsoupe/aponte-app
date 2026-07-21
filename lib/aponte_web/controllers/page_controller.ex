defmodule AponteWeb.PageController do
  use AponteWeb, :controller

  alias Aponte.Orgs

  def index(conn, _params) do
    render(conn, :index,
      orgs: Orgs.list_orgs_with_current_edition(),
      page_title: nil
    )
  end

  def sobre(conn, _params) do
    render(conn, :sobre, page_title: "Sobre")
  end

  # The notification panel moved to a section of the org's sobre page
  # (/:slug/sobre#avisos); the push POST endpoints stay org-scoped as they are.
  def avisos(conn, _params) do
    redirect(conn, to: ~p"/#{conn.assigns.org.slug}/sobre" <> "#avisos")
  end
end
