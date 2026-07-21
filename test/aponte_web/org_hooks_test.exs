defmodule AponteWeb.OrgHooksTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures
  import Phoenix.LiveViewTest

  alias AponteWeb.OrgHooks

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  describe "on_mount(:load_org)" do
    test "halts with a redirect to /admin on unknown slug" do
      assert {:halt, socket} =
               OrgHooks.on_mount(
                 :load_org,
                 %{"org_slug" => "nope"},
                 %{},
                 %Phoenix.LiveView.Socket{}
               )

      assert {:redirect, %{to: "/admin"}} = socket.redirected
    end

    test "assigns the org on hit" do
      assert {:cont, socket} =
               OrgHooks.on_mount(
                 :load_org,
                 %{"org_slug" => "sesh"},
                 %{},
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.org.slug == "sesh"
    end
  end

  describe "admin LiveViews under /admin/:org_slug" do
    test "unknown org slug 404s at the plug (before the LiveView mounts)", %{
      conn: conn,
      auth: auth
    } do
      assert conn |> authed(auth) |> get("/admin/nope/") |> html_response(404)
    end

    test "edition URL from another org halts with a redirect (spec section 8.9)", %{
      conn: conn,
      auth: auth
    } do
      other = org_fixture()
      edition = edition_fixture(%{org_id: other.id})

      assert {:error, {:redirect, %{to: "/admin/sesh"}}} =
               conn |> authed(auth) |> live(~p"/admin/sesh/edicoes/#{edition.id}")
    end

    test "cortesia URL from another org halts with a redirect", %{conn: conn, auth: auth} do
      other = org_fixture()
      edition = edition_fixture(%{org_id: other.id})

      assert {:error, {:redirect, %{to: "/admin/sesh"}}} =
               conn |> authed(auth) |> live(~p"/admin/sesh/edicoes/#{edition.id}/cortesia")
    end

    test "scanner edition URL from another org halts with a redirect", %{conn: conn, auth: auth} do
      other = org_fixture()
      edition = edition_fixture(%{org_id: other.id})

      assert {:error, {:redirect, %{to: "/admin/sesh"}}} =
               conn |> authed(auth) |> live(~p"/admin/sesh/validar/#{edition.id}")
    end
  end
end
