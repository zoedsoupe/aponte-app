defmodule Aponte.CouponsTest do
  use Aponte.DataCase, async: false

  import Aponte.Fixtures, only: [edition_fixture: 1, org_fixture: 0]

  alias Aponte.{Coupons, Repo}
  alias Aponte.Coupons.Coupon

  defp insert_order(org, attrs \\ %{}) do
    Aponte.Fixtures.insert_order(edition_fixture(%{org_id: org.id}), attrs)
  end

  defp insert_coupon(org, attrs) do
    defaults = %{
      org_id: org.id,
      code: "APO-TEST#{System.unique_integer([:positive])}",
      scope: :public,
      discount_kind: :percent,
      discount_value: 10,
      is_active: true,
      uses_count: 0
    }

    Repo.insert!(struct(%Coupon{}, Map.merge(defaults, attrs)))
  end

  describe "discount_cents/2" do
    test "percent rounds" do
      assert Coupon.discount_cents(%{discount_kind: :percent, discount_value: 10}, 10_000) == 1000
      assert Coupon.discount_cents(%{discount_kind: :percent, discount_value: 15}, 999) == 150
    end

    test "fixed is capped at the subtotal" do
      assert Coupon.discount_cents(%{discount_kind: :fixed, discount_value: 500}, 10_000) == 500
      assert Coupon.discount_cents(%{discount_kind: :fixed, discount_value: 99_999}, 3000) == 3000
    end
  end

  describe "generate_code/0" do
    test "produces a APO- prefixed code with safe alphabet" do
      assert Coupons.generate_code() =~ ~r/^APO-[A-HJ-NP-Z2-9]{4}$/
    end
  end

  describe "rules" do
    @valid_rule %{
      name: "pedido grande",
      min_order_cents: 8000,
      discount_kind: :percent,
      discount_value: 10,
      expires_in_days: 7
    }

    defp rule_attrs(extra \\ %{}), do: Map.merge(@valid_rule, extra)

    test "create_rule/2 inserts a valid rule" do
      assert {:ok, rule} = Coupons.create_rule(org_fixture(), rule_attrs())
      assert rule.is_active
    end

    test "rejects a percent discount over 100" do
      assert {:error, cs} = Coupons.create_rule(org_fixture(), rule_attrs(%{discount_value: 150}))
      assert %{discount_value: _} = errors_on(cs)
    end

    test "list_active_rules/1 excludes inactive" do
      org = org_fixture()
      {:ok, _} = Coupons.create_rule(org, rule_attrs())
      {:ok, _} = Coupons.create_rule(org, rule_attrs(%{name: "off", is_active: false}))
      assert [%{name: "pedido grande"}] = Coupons.list_active_rules(org.id)
    end
  end

  describe "create_public_coupon/2" do
    test "auto-generates a code when blank" do
      org = org_fixture()

      assert {:ok, c} =
               Coupons.create_public_coupon(org, %{
                 "discount_kind" => "percent",
                 "discount_value" => "10"
               })

      assert c.code =~ ~r/^APO-/
      assert c.scope == :public
      assert c.org_id == org.id
    end

    test "keeps a custom code, upcased" do
      assert {:ok, c} =
               Coupons.create_public_coupon(org_fixture(), %{
                 "code" => "blackfriday10",
                 "discount_kind" => "percent",
                 "discount_value" => "10"
               })

      assert c.code == "BLACKFRIDAY10"
    end
  end

  describe "issue_for_order/1" do
    setup do
      org = org_fixture()

      {:ok, rule} =
        Coupons.create_rule(org, %{
          name: "premia",
          min_order_cents: 8000,
          discount_kind: :percent,
          discount_value: 10,
          expires_in_days: 7
        })

      {:ok, org: org, rule: rule}
    end

    test "issues a bound coupon when the total meets the threshold", %{org: org, rule: rule} do
      order = insert_order(org, %{total_cents: 9000, customer_instagram: "fulano"})
      assert :ok = Coupons.issue_for_order(order)

      assert [coupon] = Coupons.earned_for_order(order.id)
      assert coupon.scope == :bound
      assert coupon.customer_instagram == "fulano"
      assert coupon.discount_kind == rule.discount_kind
      assert coupon.expires_at
    end

    test "issues nothing below the threshold", %{org: org} do
      order = insert_order(org, %{total_cents: 5000})
      assert :ok = Coupons.issue_for_order(order)
      assert Coupons.earned_for_order(order.id) == []
    end
  end

  describe "release_for_order/1" do
    test "deletes bound coupons the order earned but never used" do
      org = org_fixture()
      order = insert_order(org, %{total_cents: 9000, customer_instagram: "fulano"})

      _coupon =
        insert_coupon(org, %{scope: :bound, order_id: order.id, customer_instagram: "fulano"})

      assert [_] = Coupons.earned_for_order(order.id)
      assert :ok = Coupons.release_for_order(order)
      assert Coupons.earned_for_order(order.id) == []
    end

    test "keeps a bound coupon the order earned and already used" do
      org = org_fixture()
      order = insert_order(org, %{total_cents: 9000, customer_instagram: "fulano"})

      _coupon =
        insert_coupon(org, %{
          scope: :bound,
          order_id: order.id,
          customer_instagram: "fulano",
          used_at: Aponte.Clock.now_utc(),
          used_order_id: Ecto.UUID.generate()
        })

      assert :ok = Coupons.release_for_order(order)
      assert [_] = Coupons.earned_for_order(order.id)
    end

    test "refunds a bound coupon the order consumed" do
      org = org_fixture()
      code = "APO-BOUND1"
      order = insert_order(org, %{total_cents: 5000, coupon_code: code})

      coupon =
        insert_coupon(org, %{
          scope: :bound,
          code: code,
          customer_instagram: "fulano",
          used_at: Aponte.Clock.now_utc(),
          used_order_id: order.id
        })

      assert :ok = Coupons.release_for_order(order)
      refunded = Repo.get!(Coupon, coupon.id)
      assert refunded.used_at == nil
      assert refunded.used_order_id == nil
    end

    test "decrements a public coupon's uses_count" do
      org = org_fixture()
      code = "APO-PUB1"
      order = insert_order(org, %{total_cents: 5000, coupon_code: code})
      coupon = insert_coupon(org, %{scope: :public, code: code, uses_count: 3})

      assert :ok = Coupons.release_for_order(order)
      assert Repo.get!(Coupon, coupon.id).uses_count == 2
    end
  end

  describe "preview/2" do
    setup do
      {:ok, org: org_fixture()}
    end

    defp ctx(org, ig, subtotal), do: %{customer_instagram: ig, subtotal: subtotal, org_id: org.id}

    test "returns not_found for an unknown code", %{org: org} do
      assert {:error, :not_found} = Coupons.preview("NOPE", ctx(org, "x", 1000))
    end

    test "computes discount for a valid public coupon", %{org: org} do
      insert_coupon(org, %{code: "PUB10", discount_kind: :percent, discount_value: 10})

      assert {:ok, %Coupon{code: "PUB10"}, 1000} = Coupons.preview("PUB10", ctx(org, "x", 10_000))
    end

    test "enforces public min_order", %{org: org} do
      insert_coupon(org, %{code: "MIN50", min_order_cents: 5000})

      assert {:error, {:min_order, 5000}} = Coupons.preview("MIN50", ctx(org, "x", 3000))
    end

    test "rejects an exhausted public coupon", %{org: org} do
      insert_coupon(org, %{code: "ONE", max_uses: 1, uses_count: 1})

      assert {:error, :exhausted} = Coupons.preview("ONE", ctx(org, "x", 1000))
    end

    test "rejects an expired coupon", %{org: org} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
      insert_coupon(org, %{code: "OLD", expires_at: past})

      assert {:error, :expired} = Coupons.preview("OLD", ctx(org, "x", 1000))
    end

    test "bound coupon requires the same customer", %{org: org} do
      insert_coupon(org, %{code: "MINE", scope: :bound, customer_instagram: "alice"})

      assert {:error, :wrong_customer} = Coupons.preview("MINE", ctx(org, "bob", 1000))

      assert {:ok, _, _} = Coupons.preview("MINE", ctx(org, "@Alice", 1000))
    end

    test "bound coupon already used is rejected", %{org: org} do
      used = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_coupon(org, %{
        code: "DONE",
        scope: :bound,
        customer_instagram: "alice",
        used_at: used
      })

      assert {:error, :used} = Coupons.preview("DONE", ctx(org, "alice", 1000))
    end
  end

  describe "claim/3" do
    test "bound coupon can only be claimed once" do
      org = org_fixture()
      order = insert_order(org)
      coupon = insert_coupon(org, %{code: "B1", scope: :bound, customer_instagram: "diana"})

      assert {:ok, :claimed} = Coupons.claim(Repo, coupon, order.id)
      assert {:error, :coupon_taken} = Coupons.claim(Repo, coupon, order.id)

      assert Repo.get(Coupon, coupon.id).used_at
    end

    test "public coupon increments uses up to its cap" do
      org = org_fixture()
      order = insert_order(org)
      coupon = insert_coupon(org, %{code: "P1", scope: :public, max_uses: 2, uses_count: 0})

      assert {:ok, :claimed} = Coupons.claim(Repo, coupon, order.id)
      assert {:ok, :claimed} = Coupons.claim(Repo, coupon, order.id)
      assert {:error, :coupon_taken} = Coupons.claim(Repo, coupon, order.id)

      assert Repo.get(Coupon, coupon.id).uses_count == 2
    end
  end

  describe "notify_expiring/1" do
    setup do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, org: org_fixture(), now: now, soon: DateTime.add(now, 3600, :second)}
    end

    test "marks bound coupons expiring within 24h, skips later ones", %{
      org: org,
      now: now,
      soon: soon
    } do
      later = DateTime.add(now, 3 * 86_400, :second)

      c_soon =
        insert_coupon(org, %{
          code: "SOON",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/x",
          expires_at: soon
        })

      c_later =
        insert_coupon(org, %{
          code: "LATER",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/y",
          expires_at: later
        })

      assert :ok = Coupons.notify_expiring(now)
      assert Repo.get(Coupon, c_soon.id).notified_expiring_at
      refute Repo.get(Coupon, c_later.id).notified_expiring_at
    end

    test "skips coupons without a device", %{org: org, now: now, soon: soon} do
      c =
        insert_coupon(org, %{
          code: "NODEV",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: nil,
          expires_at: soon
        })

      assert :ok = Coupons.notify_expiring(now)
      refute Repo.get(Coupon, c.id).notified_expiring_at
    end

    test "skips already-used coupons", %{org: org, now: now, soon: soon} do
      c =
        insert_coupon(org, %{
          code: "USED",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/u",
          expires_at: soon,
          used_at: now
        })

      assert :ok = Coupons.notify_expiring(now)
      refute Repo.get(Coupon, c.id).notified_expiring_at
    end

    test "is idempotent across ticks", %{org: org, now: now, soon: soon} do
      c =
        insert_coupon(org, %{
          code: "ONCE",
          scope: :bound,
          customer_instagram: "a",
          client_endpoint: "https://push/z",
          expires_at: soon
        })

      Coupons.notify_expiring(now)
      first = Repo.get(Coupon, c.id).notified_expiring_at
      assert first

      Coupons.notify_expiring(DateTime.add(now, 60, :second))
      assert Repo.get(Coupon, c.id).notified_expiring_at == first
    end
  end
end
