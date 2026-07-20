defmodule AponteWeb.OrderControllerTest do
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures

  setup do
    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    %{org: org}
  end

  test "show 404s for an order of another org", %{conn: conn, org: sesh} do
    other_edition = edition_fixture(%{org_id: org_fixture().id})
    order = insert_order(other_edition)

    conn = get(conn, "/#{sesh.slug}/compra/#{order.id}")
    assert html_response(conn, 404)
  end

  test "show renders an order of the same org", %{conn: conn, org: sesh} do
    edition = edition_fixture(%{org_id: sesh.id})
    order = insert_order(edition)

    conn = get(conn, "/#{sesh.slug}/compra/#{order.id}")
    assert html_response(conn, 200) =~ "Pedido"
  end

  test "lookup renders the masked name on (org, phone, code) match", %{conn: conn, org: sesh} do
    edition = edition_fixture(%{org_id: sesh.id})

    order =
      insert_order(edition, %{customer_name: "Maria Silva", customer_phone: "22987654321"})

    conn =
      post(conn, "/#{sesh.slug}/meus-ingressos", %{
        "phone" => "(22) 98765-4321",
        "code" => order.id
      })

    html = html_response(conn, 200)
    assert html =~ "M. S."
    assert html =~ "/#{sesh.slug}/compra/#{order.id}"
    refute html =~ "Maria Silva"
  end

  test "lookup with wrong phone answers the generic not-found", %{conn: conn, org: sesh} do
    edition = edition_fixture(%{org_id: sesh.id})

    order =
      insert_order(edition, %{customer_name: "Maria Silva", customer_phone: "22987654321"})

    conn =
      post(conn, "/#{sesh.slug}/meus-ingressos", %{
        "phone" => "21111112222",
        "code" => order.id
      })

    html = html_response(conn, 200)
    assert html =~ "Nada encontrado"
    refute html =~ "M. S."
  end

  test "11th lookup POST within the window gets 429", %{conn: conn, org: sesh} do
    conn =
      put_req_header(conn, "fly-client-ip", "203.0.113.#{System.unique_integer([:positive])}")

    params = %{"phone" => "22999998888", "code" => Ecto.UUID.generate()}

    for _ <- 1..10 do
      assert post(conn, "/#{sesh.slug}/meus-ingressos", params).status == 200
    end

    assert post(conn, "/#{sesh.slug}/meus-ingressos", params).status == 429
  end
end
