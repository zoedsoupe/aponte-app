defmodule AponteWeb.Admin.OrgListLive do
  @moduledoc """
  Admin landing (/admin): every org (active or suspended) with a link into its
  scoped dashboard, plus the create-org entry point.
  """
  use AponteWeb, :live_view

  alias Aponte.Orgs

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, orgs: Orgs.list_orgs(), page_title: "Organizações")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <section class="stack-5">
        <div class="row space-between align-baseline">
          <h1 class="text-xl text-mono">Organizações</h1>
          <a href={~p"/admin/organizacoes/nova"} class="admin-action admin-action--primary">
            + Nova org
          </a>
        </div>

        <p :if={@orgs == []} class="text-sm text-dim">Nenhuma organização ainda.</p>

        <ul class="stack-2">
          <li :for={org <- @orgs} class="card">
            <a
              href={~p"/admin/#{org.slug}"}
              class="row space-between align-center"
              id={"org-#{org.slug}"}
            >
              <div class="stack-1">
                <span class="text-base text-accent">{org.name}</span>
                <span class="text-xs text-dim text-mono">/{org.slug}</span>
              </div>
              <span class="row gap-2">
                <span class="chip">{org.status}</span>
                <span class="chip">{org.tier}</span>
              </span>
            </a>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
