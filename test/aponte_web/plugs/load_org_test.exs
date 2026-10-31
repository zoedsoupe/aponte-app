defmodule AponteWeb.LoadOrgTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures

  alias Aponte.Notifications.PushSubscription
  alias Aponte.Repo

  test "404s on unknown slug", %{conn: conn} do
    conn = get(conn, "/nope/")
    assert html_response(conn, 404) =~ "Essa página sumiu"
  end

  test "404s on reserved slug", %{conn: conn} do
    conn = get(conn, "/aponte/")
    assert html_response(conn, 404)
  end

  test "404s on suspended org", %{conn: conn} do
    org_fixture(%{slug: "suspended-org", status: :suspended})

    conn = get(conn, "/suspended-org/")
    assert html_response(conn, 404)
  end

  test "assigns the org on hit", %{conn: conn} do
    conn = get(conn, "/sesh/")
    assert html_response(conn, 200)
    assert conn.assigns.org.slug == "sesh"
  end

  test "api variant answers JSON 404 on unknown slug", %{conn: conn} do
    conn = get(conn, "/nope/push/vapid-key")
    assert json_response(conn, 404) == %{"error" => "not found"}
  end

  test "api variant assigns the org and subscribe stamps its org_id", %{conn: conn} do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    endpoint = "https://push.example.com/#{System.unique_integer([:positive])}"

    body = %{
      "subscription" => %{
        "endpoint" => endpoint,
        "keys" => %{"p256dh" => "BPdh-key", "auth" => "auth-secret"}
      }
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/sesh/push/subscribe", JSON.encode!(body))

    assert json_response(conn, 201) == %{"ok" => true}
    assert conn.assigns.org.id == org.id
    assert Repo.get_by!(PushSubscription, endpoint: endpoint).org_id == org.id
  end
end
