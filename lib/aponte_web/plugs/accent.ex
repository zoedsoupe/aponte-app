defmodule AponteWeb.Plugs.Accent do
  @moduledoc """
  Assina `@accent` com a cor da org carregada (`assigns[:org].accent_color`),
  caindo no accent padrão da Aponte (`config :aponte, :default_accent`) em
  páginas sem org. A CSS var `--accent` re-tematiza a página via o style
  inline no <html>.

  Deve rodar DEPOIS do LoadOrg (não fica mais no :browser). Controllers podem
  sobrescrever `@accent` depois (ex: a página de compra usa o accent da edição
  específica do pedido).
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    assign(conn, :accent, accent(conn.assigns[:org]))
  end

  defp accent(%{accent_color: color}) when is_binary(color), do: color

  defp accent(_), do: Application.get_env(:aponte, :default_accent, "#BF7262")
end
