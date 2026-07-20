defmodule AponteWeb.LegacyRedirectController do
  @moduledoc """
  TEMPORARY: 301s the pre-multi-org global paths to their `/:org_slug/...`
  equivalents under the `sesh` org, so old bookmarks, DM'd order links and
  client-side localStorage links keep working until phase 6 rewrites them.

  Removal trigger: 30 days after the domain cutover (SPEC_APONTE_V1 sec. 6).
  """

  use AponteWeb, :controller

  @org "sesh"

  def comprar(conn, _params), do: moved(conn, "/#{@org}/comprar")
  def compra(conn, %{"id" => id}), do: moved(conn, "/#{@org}/compra/#{id}")
  def meus_ingressos(conn, _params), do: moved(conn, "/#{@org}/meus-ingressos")
  def loja(conn, _params), do: moved(conn, "/#{@org}/loja")
  def avisos(conn, _params), do: moved(conn, "/#{@org}/avisos")
  def tocar(conn, _params), do: moved(conn, "/#{@org}/tocar")

  defp moved(conn, target) do
    conn
    |> put_resp_header("location", target)
    |> send_resp(301, "")
  end
end
