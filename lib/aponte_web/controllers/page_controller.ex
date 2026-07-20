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

  # Notification config panel. Stateless shell — the toggle/topics reflect the
  # device's own subscription, managed client-side (assets/js/client_push.js).
  # The data-push-* URLs point at this org's push endpoints (read by phase 6).
  def avisos(conn, _params) do
    render(conn, :avisos, org: conn.assigns.org, page_title: "Avisos")
  end
end
