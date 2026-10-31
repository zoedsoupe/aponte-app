defmodule AponteWeb.Layouts do
  @moduledoc false
  use AponteWeb, :html

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  @doc false
  # Inline CSS-var overrides on <html>. Plugs.Accent always assigns @theme;
  # the @accent fallback covers render paths that skip the plug. color-scheme
  # follows the page bg luminance so dark orgs get dark native form controls.
  def theme_style(assigns) do
    case assigns[:theme] do
      %{bg: bg, ink: ink, accent: accent}
      when is_binary(bg) and is_binary(ink) and is_binary(accent) ->
        "--bg: #{bg}; --ink: #{ink}; --accent: #{accent}; color-scheme: #{color_scheme(bg)}"

      _ ->
        case assigns[:accent] do
          nil -> nil
          accent -> "--accent: #{accent}"
        end
    end
  end

  defp color_scheme(bg), do: if(dark_color?(bg), do: "dark", else: "light")

  # Perceived luminance (Rec. 601) of a #RRGGBB hex color; < 128 reads as dark.
  # Anything unparseable falls back to light (the platform default).
  defp dark_color?("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    with {rv, ""} <- Integer.parse(r, 16),
         {gv, ""} <- Integer.parse(g, 16),
         {bv, ""} <- Integer.parse(b, 16) do
      0.299 * rv + 0.587 * gv + 0.114 * bv < 128
    else
      _ -> false
    end
  end

  defp dark_color?(_), do: false

  attr :flash, :map, default: %{}
  attr :org, :map, default: nil, doc: "loaded org on org-scoped pages; nil on the Aponte shell"

  attr :current_path, :string,
    default: nil,
    doc: "conn.request_path, for the tab bar active state"

  attr :site_header, :boolean,
    default: true,
    doc: "shell top bar; off on the Aponte brand pages, where the hero carries the brand"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="shell">
      <%!-- org pages carry zero Aponte branding and no top bar: navigation is
           the tab bar (bottom on mobile, slim top bar on desktop). The header
           belongs to the Aponte shell only — and even there the brand pages
           (home, /sobre) drop it: the hero carries the brand and the nav is
           redundant with the page actions. --%>
      <header :if={is_nil(@org) and @site_header} class="site-header">
        <a href={~p"/"} class="brand row gap-2 align-center">
          <img src={~p"/images/aponte-logo.png"} alt="Aponte" class="brand-logo" />
          <span class="brand-name">Aponte</span>
        </a>
        <nav class="site-nav row gap-3 align-center">
          <a href={~p"/sobre"}>Sobre</a>
        </nav>
      </header>

      <main class="site-main">
        {render_slot(@inner_block)}
      </main>

      <.tab_bar :if={@org} org={@org} current_path={@current_path} />

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, default: %{}
  attr :back, :string, default: nil, doc: "back-link label; omit on root (/admin)"
  attr :back_to, :string, default: nil, doc: "back-link target"
  attr :org, :map, default: nil, doc: "loaded org inside /admin/:org_slug; nil on /admin"

  attr :current_path, :string,
    default: nil,
    doc: "request path (OrgHooks :admin_path), for the admin tab bar active state"

  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, back_to: assigns.back_to || admin_back_to(assigns.org))

    ~H"""
    <div class="shell shell--admin">
      <%!-- slim in-shell header: breadcrumb + config links. Daily-ops nav is
           the admin tab bar below (same chrome as the public pages). --%>
      <header class="admin-top">
        <a
          href={~p"/admin/"}
          class="text-mono text-xs text-dim"
        >
          /admin
        </a>
        <nav class="admin-top-nav" aria-label="Configurações">
          <span :if={@org} class="admin-swatches" title={"tema de #{@org.name}"}>
            <span class="swatch" style={"background-color:#{theme_color(@org, :bg_color, "#FAF5EC")}"}>
            </span>
            <span class="swatch" style={"background-color:#{theme_color(@org, :fg_color, "#49422F")}"}>
            </span>
            <span class="swatch" style={"background-color:#{@org.accent_color}"}></span>
          </span>
          <a :if={@org} href={~p"/admin/#{@org.slug}/perfil"}>Perfil</a>
          <a :if={@org} href={~p"/admin/#{@org.slug}/galeria"}>Galeria</a>
          <a :if={@org} href={~p"/admin/#{@org.slug}/cupons"}>Cupons</a>
          <a :if={@org && @org.slug == "sesh"} href={~p"/admin/#{@org.slug}/tocar"}>Tocar</a>
          <a href={if @org, do: ~p"/#{@org.slug}", else: ~p"/"}>Site</a>
        </nav>
      </header>

      <main class="site-main">
        <a :if={@back} href={@back_to} class="admin-back text-xs text-dim">← {@back}</a>
        {render_slot(@inner_block)}
      </main>

      <.admin_tab_bar :if={@org} org={@org} current_path={@current_path} />

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp admin_back_to(nil), do: "/admin"
  defp admin_back_to(org), do: "/admin/#{org.slug}"

  defp theme_color(org, field, fallback) do
    case Map.get(org, field) do
      color when is_binary(color) and color != "" -> color
      _ -> fallback
    end
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :kind, :atom, required: true
  attr :flash, :map, required: true
  attr :title, :string, default: nil

  def flash(assigns) do
    msg = Phoenix.Flash.get(assigns.flash, assigns.kind)
    assigns = assign(assigns, msg: msg, dom_id: assigns.id || "flash-#{assigns.kind}")

    ~H"""
    <div
      :if={@msg}
      id={@dom_id}
      class={"flash flash--#{@kind}"}
      role="alert"
      phx-hook="Flash"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind})}
      title="toque pra dispensar"
    >
      <p :if={@title} class="flash-title">{@title}</p>
      <p>{@msg}</p>
    </div>
    """
  end
end
