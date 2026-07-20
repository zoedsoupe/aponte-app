defmodule AponteWeb.RedirectLegacyHostTest do
  use AponteWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:aponte, :legacy_host_redirects)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:aponte, :legacy_host_redirects, previous),
        else: Application.delete_env(:aponte, :legacy_host_redirects)
    end)

    :ok
  end

  test "301s a legacy host preserving path and query", %{conn: conn} do
    Application.put_env(:aponte, :legacy_host_redirects, %{"old.test" => "aponte.fly.dev"})

    conn = get(%{conn | host: "old.test"}, "/sobre?utm=x")

    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["https://aponte.fly.dev/sobre?utm=x"]
  end

  test "passes through hosts not in the map", %{conn: conn} do
    Application.put_env(:aponte, :legacy_host_redirects, %{"old.test" => "aponte.fly.dev"})

    conn = get(conn, "/sobre")
    assert html_response(conn, 200)
  end

  test "empty config disables the plug", %{conn: conn} do
    Application.delete_env(:aponte, :legacy_host_redirects)

    conn = get(%{conn | host: "sesh-lab.fly.dev"}, "/sobre")
    assert html_response(conn, 200)
  end
end
