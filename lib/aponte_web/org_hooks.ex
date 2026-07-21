defmodule AponteWeb.OrgHooks do
  @moduledoc """
  on_mount hooks for org-scoped admin LiveViews (live_session :admin).

  Plugs.LoadOrg already 404'd unknown slugs on the HTTP render; this hook
  re-fetches the org so the LiveView process owns the `:org` assign (plug
  assigns do not cross into the LV on reconnect) and halts to /admin if the
  org disappeared in between (suspend/delete race).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias Aponte.Orgs

  def on_mount(:load_org, %{"org_slug" => slug}, _session, socket) do
    case Orgs.get_org_by_slug(slug) do
      {:ok, org} -> {:cont, assign(socket, :org, org)}
      {:error, :not_found} -> {:halt, redirect(socket, to: "/admin")}
    end
  end
end
