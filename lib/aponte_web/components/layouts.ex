defmodule AponteWeb.Layouts do
  @moduledoc false
  use AponteWeb, :html

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  @doc false
  # Inline CSS-var overrides on <html>. Plugs.Accent always assigns @theme;
  # the @accent fallback covers render paths that skip the plug.
  def theme_style(assigns) do
    case assigns[:theme] do
      %{bg: bg, ink: ink, accent: accent}
      when is_binary(bg) and is_binary(ink) and is_binary(accent) ->
        "--bg: #{bg}; --ink: #{ink}; --accent: #{accent}"

      _ ->
        case assigns[:accent] do
          nil -> nil
          accent -> "--accent: #{accent}"
        end
    end
  end

  attr :flash, :map, default: %{}
  attr :org, :map, default: nil, doc: "loaded org on org-scoped pages; nil on the Aponte shell"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="shell">
      <header class="site-header">
        <%= if @org do %>
          <a href={~p"/#{@org.slug}"} class="brand">
            <.sesh_logo />
          </a>
          <nav class="site-nav row gap-3 align-center">
            <a href={~p"/#{@org.slug}/loja"}>Loja</a>
            <a href={~p"/#{@org.slug}/meus-ingressos"}>Ingressos</a>
            <a href={~p"/#{@org.slug}/avisos"}>Avisos</a>
          </nav>
        <% else %>
          <a href={~p"/"} class="brand row gap-2 align-center">
            <img src={~p"/images/aponte-logo.jpg"} alt="Aponte" class="brand-logo" />
            <span class="brand-name">Aponte</span>
          </a>
          <nav class="site-nav row gap-3 align-center">
            <a href={~p"/sobre"}>Sobre</a>
          </nav>
        <% end %>
      </header>

      <main class="site-main">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, default: %{}
  attr :back, :string, default: nil, doc: "back-link label; omit on root (/admin)"
  attr :back_to, :string, default: nil, doc: "back-link target"
  attr :org, :map, default: nil, doc: "loaded org inside /admin/:org_slug; nil on /admin"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, back_to: assigns.back_to || admin_back_to(assigns.org))

    ~H"""
    <div class="shell shell--admin">
      <header class="site-header">
        <a href={~p"/admin"} class="brand row gap-2 align-center">
          <.sesh_logo class="sesh-logo--sm" />
          <span class="text-mono text-xs text-dim">
            {if @org, do: "/admin/#{@org.slug}", else: "/admin"}
          </span>
        </a>
        <nav class="site-nav row gap-3 align-center">
          <span :if={@org} class="row gap-1 align-center" title={"tema de #{@org.name}"}>
            <span class="swatch" style={"background-color:#{theme_color(@org, :bg_color, "#FEF8DA")}"}>
            </span>
            <span class="swatch" style={"background-color:#{theme_color(@org, :fg_color, "#49422F")}"}>
            </span>
            <span class="swatch" style={"background-color:#{@org.accent_color}"}></span>
          </span>
          <a :if={@org} href={~p"/admin/#{@org.slug}/perfil"}>Perfil</a>
          <a :if={@org} href={~p"/admin/#{@org.slug}/galeria"}>Galeria</a>
          <a href={~p"/"}>Site</a>
        </nav>
      </header>

      <main class="site-main">
        <a :if={@back} href={@back_to} class="text-xs text-dim">← {@back}</a>
        {render_slot(@inner_block)}
      </main>

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
