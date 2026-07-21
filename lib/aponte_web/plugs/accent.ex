defmodule AponteWeb.Plugs.Accent do
  @moduledoc """
  Assina o tema da página a partir da org carregada (`assigns[:org]`):

  * `@accent` — `org.accent_color`, caindo no accent padrão da Aponte
    (`config :aponte, :default_accent`) em páginas sem org.
  * `@theme` — `%{bg, ink, accent}` com as três alavancas de cor da org
    (`bg_color`/`fg_color`/`accent_color`), derivando dos defaults da Aponte
    (`:default_bg` / `:default_ink` / `:default_accent`) quando a org não
    customiza. O root layout emite as CSS vars `--bg`/`--ink`/`--accent`
    inline no <html>.

  Deve rodar DEPOIS do LoadOrg (não fica mais no :browser). Controllers podem
  sobrescrever o accent depois (ex: a página de compra usa o accent da edição
  específica do pedido) — `assign_edition_accent/2` mantém `@theme` coerente.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    org = conn.assigns[:org]
    accent = org_color(org, :accent_color) || default(:default_accent, "#BF7262")

    theme = %{
      bg: org_color(org, :bg_color) || default(:default_bg, "#FEF8DA"),
      ink: org_color(org, :fg_color) || default(:default_ink, "#49422F"),
      accent: accent
    }

    conn |> assign(:accent, accent) |> assign(:theme, theme)
  end

  @doc "Overrides the page accent (and `@theme.accent`) with an edition's color."
  def assign_edition_accent(conn, nil), do: conn

  def assign_edition_accent(conn, %{accent_color: color}) when is_binary(color) do
    theme = Map.put(conn.assigns[:theme] || %{bg: nil, ink: nil, accent: nil}, :accent, color)

    conn |> assign(:accent, color) |> assign(:theme, theme)
  end

  defp org_color(nil, _field), do: nil

  defp org_color(org, field) do
    case Map.get(org, field) do
      color when is_binary(color) and color != "" -> color
      _ -> nil
    end
  end

  defp default(key, fallback), do: Application.get_env(:aponte, key, fallback)
end
