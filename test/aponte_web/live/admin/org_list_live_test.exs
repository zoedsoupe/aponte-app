defmodule AponteWeb.Admin.OrgListLiveTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures
  import Phoenix.LiveViewTest

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "requires basic auth", %{conn: conn} do
    assert get(conn, ~p"/admin").status == 401
  end

  test "lists all orgs with status/tier and links into their dashboards", %{
    conn: conn,
    auth: auth
  } do
    org_fixture(%{slug: "arena", name: "A Arena"})

    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin")

    assert has_element?(view, "#org-sesh", "SESH")
    assert has_element?(view, "#org-arena", "A Arena")
    assert has_element?(view, ~s|a[href="/admin/sesh"]|)
    assert has_element?(view, ~s|a[href="/admin/arena"]|)
    assert has_element?(view, ~s|a[href="/admin/organizacoes/nova"]|)
    assert render(view) =~ "active"
  end
end
