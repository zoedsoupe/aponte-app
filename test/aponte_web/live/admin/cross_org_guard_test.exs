defmodule AponteWeb.Admin.CrossOrgGuardTest do
  @moduledoc """
  Cross-org URL-tampering guards (spec section 8): edit routes for products,
  coupons and coupon rules must not open a record of another org — they
  redirect to the admin org root instead.
  """
  use AponteWeb.ConnCase, async: false

  import Aponte.Fixtures
  import Phoenix.LiveViewTest

  alias Aponte.{Coupons, Merch}

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    {:ok, sesh} = Aponte.Orgs.get_org_by_slug("sesh")
    %{auth: auth, sesh: sesh, other: org_fixture()}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  defp public_coupon(org, code) do
    {:ok, coupon} =
      Coupons.create_public_coupon(org, %{
        "code" => code,
        "discount_kind" => "percent",
        "discount_value" => "10"
      })

    coupon
  end

  defp rule(org) do
    {:ok, rule} =
      Coupons.create_rule(org, %{
        name: "pedido grande",
        min_order_cents: 8000,
        discount_kind: :percent,
        discount_value: 10
      })

    rule
  end

  describe "records of another org redirect to the admin org root" do
    test "product edit", %{conn: conn, auth: auth, other: other} do
      {:ok, item} = Merch.create_item(other, %{name: "Poster", price_cents: 2000, stock: 10})

      assert {:error, {:redirect, %{to: "/admin/sesh"}}} =
               conn |> authed(auth) |> live(~p"/admin/sesh/produtos/#{item.id}")
    end

    test "coupon edit", %{conn: conn, auth: auth, other: other} do
      coupon = public_coupon(other, "OUTRAORG")

      assert {:error, {:redirect, %{to: "/admin/sesh"}}} =
               conn |> authed(auth) |> live(~p"/admin/sesh/cupons/#{coupon.id}")
    end

    test "coupon rule edit", %{conn: conn, auth: auth, other: other} do
      rule = rule(other)

      assert {:error, {:redirect, %{to: "/admin/sesh"}}} =
               conn |> authed(auth) |> live(~p"/admin/sesh/cupons/regras/#{rule.id}")
    end
  end

  describe "records of the scoped org still render" do
    test "product edit", %{conn: conn, auth: auth, sesh: sesh} do
      {:ok, item} = Merch.create_item(sesh, %{name: "Poster", price_cents: 2000, stock: 10})

      {:ok, _view, html} = conn |> authed(auth) |> live(~p"/admin/sesh/produtos/#{item.id}")
      assert html =~ "Poster"
    end

    test "coupon edit", %{conn: conn, auth: auth, sesh: sesh} do
      coupon = public_coupon(sesh, "DASESH10")

      {:ok, _view, html} = conn |> authed(auth) |> live(~p"/admin/sesh/cupons/#{coupon.id}")
      assert html =~ "Editar cupom"
    end

    test "coupon rule edit", %{conn: conn, auth: auth, sesh: sesh} do
      rule = rule(sesh)

      {:ok, _view, html} =
        conn |> authed(auth) |> live(~p"/admin/sesh/cupons/regras/#{rule.id}")

      assert html =~ "Editar regra"
    end
  end
end
