defmodule AponteWeb.LegacyRedirectControllerTest do
  use AponteWeb.ConnCase, async: false

  test "legacy paths 301 to their /sesh/ equivalents", %{conn: conn} do
    for {from, to} <- [
          {"/comprar", "/sesh/comprar"},
          {"/meus-ingressos", "/sesh/meus-ingressos"},
          {"/loja", "/sesh/loja"},
          {"/avisos", "/sesh/avisos"},
          {"/tocar", "/sesh/tocar"}
        ] do
      conn = get(conn, from)
      assert conn.status == 301
      assert get_resp_header(conn, "location") == [to]
    end
  end

  test "legacy order links keep the id", %{conn: conn} do
    id = Ecto.UUID.generate()

    conn = get(conn, "/compra/#{id}")
    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["/sesh/compra/#{id}"]
  end
end
