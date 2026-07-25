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
  Bottom tab bar for org pages (mobile chrome; docked top bar on desktop).
  Tabs: Inicio (vitrine), Galeria, Loja, Pedidos (meus-ingressos), Sobre —
  Sobre trailing. Galeria hides when the org has no gallery images (the count
  rides on the org map, assigned by Plugs.LoadOrg). The active tab is derived
  server-side from `current_path` (conn.request_path).
  """
  attr :org, :map, required: true
  attr :current_path, :string, default: nil

  def tab_bar(assigns) do
    assigns = assign(assigns, :show_gallery, Map.get(assigns.org, :gallery_count, 1) > 0)

    ~H"""
    <nav class="tab-bar" aria-label={"Navegação, #{@org.name}"}>
      <span class="tab-bar-wordmark" aria-hidden="true">{@org.name}</span>
      <.tab_item
        href={~p"/#{@org.slug}"}
        icon={:home}
        label="Início"
        active={active_tab?(@current_path, ~p"/#{@org.slug}", :exact)}
      />
      <.tab_item
        :if={@show_gallery}
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
        label="Pedidos"
        active={
          active_tab?(@current_path, ~p"/#{@org.slug}/meus-ingressos", :prefix) or
            active_tab?(@current_path, ~p"/#{@org.slug}/comprar", :prefix) or
            active_tab?(@current_path, "/#{@org.slug}/compra", :prefix)
        }
      />
      <.tab_item
        href={~p"/#{@org.slug}/sobre"}
        icon={:info}
        label="Sobre"
        active={active_tab?(@current_path, ~p"/#{@org.slug}/sobre", :prefix)}
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

  defp tab_icon(%{name: :tag} = assigns) do
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
      <path d="M4 4h6.5L20 13.5a1.5 1.5 0 0 1 0 2.1l-4.4 4.4a1.5 1.5 0 0 1-2.1 0L4 10.5V4Z" />
      <circle cx="8.5" cy="8.5" r="1.2" />
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

  defp tab_icon(%{name: :scan} = assigns) do
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
      <rect x="4" y="4" width="6.5" height="6.5" rx="1" />
      <rect x="13.5" y="4" width="6.5" height="6.5" rx="1" />
      <rect x="4" y="13.5" width="6.5" height="6.5" rx="1" />
      <path d="M13.5 13.5h2.7v2.7h-2.7z" />
      <path d="M17.3 17.3H20V20h-2.7z" />
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
  Admin tab bar: the daily-ops surfaces (Painel, Pedidos, Porta, Balcão,
  Produtos). Same chrome language as the public tab bar — bottom bar on
  mobile, slim frosted top bar on desktop. Config pages (Perfil, Galeria,
  Cupons, DJ) stay in the admin header; edition-scoped actions (Cortesia,
  Editar) live in the dashboard's edition section.
  """
  attr :org, :map, required: true
  attr :current_path, :string, default: nil

  def admin_tab_bar(assigns) do
    ~H"""
    <nav class="tab-bar" aria-label="Administração">
      <.tab_item
        href={~p"/admin/#{@org.slug}"}
        icon={:home}
        label="Painel"
        active={active_tab?(@current_path, ~p"/admin/#{@org.slug}", :exact)}
      />
      <.tab_item
        href={~p"/admin/#{@org.slug}/buscar"}
        icon={:ticket}
        label="Pedidos"
        active={
          active_tab?(@current_path, ~p"/admin/#{@org.slug}/buscar", :prefix) or
            active_tab?(@current_path, "/admin/#{@org.slug}/pedidos", :prefix)
        }
      />
      <.tab_item
        href={~p"/admin/#{@org.slug}/validar"}
        icon={:scan}
        label="Porta"
        active={active_tab?(@current_path, ~p"/admin/#{@org.slug}/validar", :prefix)}
      />
      <.tab_item
        href={~p"/admin/#{@org.slug}/balcao"}
        icon={:bag}
        label="Balcão"
        active={active_tab?(@current_path, ~p"/admin/#{@org.slug}/balcao", :exact)}
      />
      <.tab_item
        href={~p"/admin/#{@org.slug}/produtos"}
        icon={:tag}
        label="Produtos"
        active={active_tab?(@current_path, ~p"/admin/#{@org.slug}/produtos", :prefix)}
      />
    </nav>
    """
  end

  @doc """
  Admin page header: display h1 with an optional eyebrow line and a
  right-aligned actions slot (primary CTA, toggles). Sets the hierarchy
  every admin page shares.
  """
  attr :title, :string, required: true
  attr :eyebrow, :string, default: nil
  slot :actions

  def admin_header(assigns) do
    ~H"""
    <header class="admin-header">
      <div class="stack-1">
        <p :if={@eyebrow} class="eyebrow">{@eyebrow}</p>
        <h1 class="text-xl">{@title}</h1>
      </div>
      <div :if={@actions != []} class="admin-header-actions">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Dashboard stat card: mono value over a small uppercase label, on a
  surface panel. Renders inside a `.stat-grid` container.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true

  def stat_card(assigns) do
    ~H"""
    <div class="stat">
      <span class="stat-value">{@value}</span>
      <span class="stat-label">{@label}</span>
    </div>
    """
  end

  @doc """
  Native quantity stepper: −/+ buttons around a number input. Wired by
  assets/js/stepper.js (`data-stepper*` hooks), which clamps to [0, max] and
  re-fires `input` so listeners (form gate, totals) stay in sync. Submits a
  plain scalar under `name`, so params shape is unchanged.
  """
  attr :name, :string, required: true
  attr :value, :any, default: 0
  attr :max, :any, default: nil
  attr :label, :string, default: nil, doc: "item name, used for aria labels"

  def qty_stepper(assigns) do
    ~H"""
    <div class="stepper" data-stepper data-max={@max}>
      <button
        type="button"
        class="stepper-btn"
        data-stepper-decr
        aria-label={if @label, do: "diminuir #{@label}", else: "diminuir"}
      >
        −
      </button>
      <input
        type="number"
        name={@name}
        value={@value}
        min="0"
        max={@max}
        step="1"
        inputmode="numeric"
        class="stepper-input"
        data-stepper-input
        aria-label={if @label, do: "quantidade: #{@label}", else: "quantidade"}
      />
      <button
        type="button"
        class="stepper-btn"
        data-stepper-incr
        aria-label={if @label, do: "aumentar #{@label}", else: "aumentar"}
      >
        +
      </button>
    </div>
    """
  end

  @doc """
  Form section with the design system's small uppercase label and an optional
  hint. Groups a purchase-flow (or admin) form into titled blocks.
  """
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <section class={["stack-3", @class]}>
      <header class="stack-1">
        <h2 class="section-label">{@title}</h2>
        <p :if={@hint} class="text-xs text-dim">{@hint}</p>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Label + control wrapper for raw inputs (no changeset binding, e.g. the
  phone/code lookup). Changeset-bound fields should use `input/1` from
  CoreComponents instead.
  """
  attr :for, :string, required: true
  attr :label, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <div class="field">
      <label for={@for} class="field-label">{@label}</label>
      {render_slot(@inner_block)}
      <p :if={@hint} class="text-xs text-dim">{@hint}</p>
    </div>
    """
  end

  @doc """
  Sticky submit dock for long purchase forms: pins the primary action to the
  bottom of the viewport (above the tab bar on mobile) while the form scrolls.
  Renders in normal flow, so it never covers content.
  """
  slot :inner_block, required: true

  def form_bar(assigns) do
    ~H"""
    <div class="form-bar">{render_slot(@inner_block)}</div>
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
      <img src={~p"/images/aponte-logo.png"} alt="" loading="lazy" />
    </div>
    """
  end
end
