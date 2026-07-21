defmodule AponteWeb.OrgHooks do
  @moduledoc """
  on_mount hooks for org-scoped admin LiveViews (live_session :admin).

  Plugs.LoadOrg already 404'd unknown slugs on the HTTP render; this hook
  re-fetches the org so the LiveView process owns the `:org` assign (plug
  assigns do not cross into the LV on reconnect) and halts to /admin if the
  org disappeared in between (suspend/delete race).

  Also tracks `:admin_path` (current request path) via a handle_params hook
  so the admin tab bar can mark the active tab.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias Aponte.Orgs

  def on_mount(:load_org, %{"org_slug" => slug}, _session, socket) do
    case Orgs.get_org_by_slug(slug) do
      {:ok, org} ->
        {:cont, socket |> assign(:org, org) |> track_admin_path()}

      {:error, :not_found} ->
        {:halt, redirect(socket, to: "/admin")}
    end
  end

  # handle_params hooks require a router-mounted view; bare unit-test sockets
  # (%Phoenix.LiveView.Socket{}) have no router and skip the tracking.
  defp track_admin_path(%{router: nil} = socket), do: socket

  defp track_admin_path(socket) do
    attach_hook(socket, :admin_path, :handle_params, fn _params, uri, socket ->
      {:cont, assign(socket, :admin_path, URI.parse(uri).path)}
    end)
  end
end
