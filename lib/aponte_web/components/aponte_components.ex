defmodule AponteWeb.AponteComponents do
  @moduledoc """
  Aponte design-system components: app chrome (bottom tab bar, floating CTA)
  and the brand hand motif. Everything renders from the org theme CSS vars
  (`--bg`/`--ink`/`--accent`), so the same markup serves the cream Aponte
  shell and dark orgs like SESH.
  """

  use Phoenix.Component
  use AponteWeb, :verified_routes

  @doc """
  Bottom tab bar for org pages (mobile chrome; hidden on desktop by CSS).
  Tabs: Inicio (vitrine), Sobre, Galeria, Loja, Ingressos (meus-ingressos).
  The active tab is derived server-side from `current_path`
  (conn.request_path).
  """
  attr :org, :map, required: true
  attr :current_path, :string, default: nil

  def tab_bar(assigns) do
    ~H"""
    <nav class="tab-bar" aria-label="Navegação da organização">
      <.tab_item
        href={~p"/#{@org.slug}"}
        icon={:home}
        label="Início"
        active={active_tab?(@current_path, ~p"/#{@org.slug}", :exact)}
      />
      <.tab_item
        href={~p"/#{@org.slug}/sobre"}
        icon={:info}
        label="Sobre"
        active={active_tab?(@current_path, ~p"/#{@org.slug}/sobre", :prefix)}
      />
      <.tab_item
        href={~p"/#{@org.slug}/galeria"}
        icon={:image}
        label="Galeria"
        active={active_tab?(@current_path, ~p"/#{@org.slug}/galeria", :prefix)}
      />
      <.tab_item
        href={~p"/#{@org.slug}/loja"}
        icon={:bag}
        label="Loja"
        active={active_tab?(@current_path, ~p"/#{@org.slug}/loja", :prefix)}
      />
      <.tab_item
        href={~p"/#{@org.slug}/meus-ingressos"}
        icon={:ticket}
        label="Ingressos"
        active={active_tab?(@current_path, ~p"/#{@org.slug}/meus-ingressos", :prefix)}
      />
    </nav>
    """
  end

  # Home matches only the vitrine itself ("/sesh" or "/sesh/"); section tabs
  # match their subtree ("/sesh/loja", "/sesh/loja/...").
  defp active_tab?(nil, _href, _mode), do: false

  defp active_tab?(path, href, :exact) do
    path == href or path == href <> "/"
  end

  defp active_tab?(path, href, :prefix) do
    path == href or String.starts_with?(path, href <> "/")
  end

  attr :href, :string, required: true
  attr :icon, :atom, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp tab_item(assigns) do
    ~H"""
    <a href={@href} class={["tab-item", @active && "is-active"]} aria-current={@active && "page"}>
      <.tab_icon name={@icon} />
      <span class="tab-item-label">{@label}</span>
    </a>
    """
  end

  # Minimal 24x24 stroke icons (currentColor, 1.6 stroke, round joins).
  defp tab_icon(%{name: :home} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M4 11.5 12 4.5l8 7" />
      <path d="M6.5 10v9h11v-9" />
    </svg>
    """
  end

  defp tab_icon(%{name: :bag} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M6 8h12l-1.2 12H7.2L6 8Z" />
      <path d="M9 10V7a3 3 0 0 1 6 0v3" />
    </svg>
    """
  end

  defp tab_icon(%{name: :ticket} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M4 8a1 1 0 0 0-1 1v2a3 3 0 1 1 0 6v2a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-2a3 3 0 1 1 0-6V9a1 1 0 0 0-1-1H4Z" />
      <path d="M14 8v1.5" />
      <path d="M14 12.5v1.5" />
      <path d="M14 17v1.5" />
    </svg>
    """
  end

  defp tab_icon(%{name: :info} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 11v5" />
      <path d="M12 7.5v.5" />
    </svg>
    """
  end

  defp tab_icon(%{name: :image} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <rect x="4" y="5" width="16" height="14" rx="1.5" />
      <circle cx="9.5" cy="10" r="1.5" />
      <path d="m5 17 4.5-4.5 3 3L17 11l2 2" />
    </svg>
    """
  end

  @doc """
  The comprar call-to-action. Floats above the tab bar on mobile (hides on
  scroll down, returns on scroll up — see scroll_fx.js); on desktop it is
  hidden and the docked inline CTA in the page body takes over.
  """
  attr :href, :string, required: true
  attr :label, :string, required: true

  def floating_cta(assigns) do
    ~H"""
    <div class="floating-cta" data-floating-cta>
      <a href={@href} class="btn btn--blob btn--block floating-cta-btn">{@label}</a>
    </div>
    """
  end

  @doc """
  The watercolor pointing hand, presented as a tilted print with feathered
  edges. The index finger is rotated to aim at the page's primary action
  (down-right toward the floating CTA on mobile, right toward the content
  column on desktop). Decorative: hidden from assistive tech.
  """
  attr :class, :string, default: nil

  def hand_motif(assigns) do
    ~H"""
    <div class={["hand-print", @class]} aria-hidden="true">
      <img src={~p"/images/aponte-logo.jpg"} alt="" loading="lazy" />
    </div>
    """
  end
end
