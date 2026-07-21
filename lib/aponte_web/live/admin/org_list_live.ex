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
        <.admin_header title="Organizações" eyebrow="Aponte">
          <:actions>
            <a href={~p"/admin/organizacoes/nova"} class="admin-action admin-action--primary">
              + Nova org
            </a>
          </:actions>
        </.admin_header>

        <p :if={@orgs == []} class="text-sm text-dim">Nenhuma organização ainda.</p>

        <ul :if={@orgs != []} class="inset-list">
          <li :for={org <- @orgs}>
            <a href={~p"/admin/#{org.slug}"} class="inset-row" id={"org-#{org.slug}"}>
              <span class="stack-1">
                <span class="text-base">{org.name}</span>
                <span class="text-xs text-dim text-mono">/{org.slug}</span>
              </span>
              <span class="row gap-2 align-center">
                <span class="chip">{org.status}</span>
                <span class="chip">{org.tier}</span>
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.6"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  class="inset-chev"
                  aria-hidden="true"
                >
                  <path d="m9 5 7 7-7 7" />
                </svg>
              </span>
            </a>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
