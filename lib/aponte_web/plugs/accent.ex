defmodule AponteWeb.Plugs.Accent do
  @moduledoc """
  Assina `@accent` com a cor da edição publicada para que TODA página (pública
  e admin, dead view e LiveView) se re-tematize via a CSS var `--accent`.

  Sem edição publicada → não assina nada e o `tokens.css` cai no rosa padrão.
  Controllers podem sobrescrever `@accent` depois (ex: a página de compra usa o
  accent da edição específica do pedido).
  """

  import Plug.Conn

  alias Aponte.{Editions, Orgs}

  def init(opts), do: opts

  def call(conn, _opts) do
    # TODO(phase-4): org comes from assigns (LoadOrg plug)
    with {:ok, org} <- Orgs.get_org_by_slug("sesh"),
         color when is_binary(color) <- Editions.current_accent(org.id) do
      assign(conn, :accent, color)
    else
      _ -> conn
    end
  end
end
