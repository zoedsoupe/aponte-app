defmodule Aponte.Tickets.OrderTest do
  use Aponte.DataCase, async: false

  alias Aponte.Tickets.Order

  @base %{customer_name: "Maria Silva", total_cents: 1000}

  describe "changeset buyer identity" do
    test "invalid with neither instagram nor phone" do
      changeset = Order.changeset(%Order{}, @base)

      refute changeset.valid?
      assert %{customer_instagram: ["informe instagram ou WhatsApp"]} = errors_on(changeset)
    end

    test "valid with instagram only (legacy shape)" do
      changeset = Order.changeset(%Order{}, Map.put(@base, :customer_instagram, "@Maria"))

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :customer_instagram) == "maria"
    end

    test "valid with phone only" do
      changeset = Order.changeset(%Order{}, Map.put(@base, :customer_phone, "22998765432"))

      assert changeset.valid?
    end

    test "valid with both" do
      changeset =
        Order.changeset(%Order{}, %{
          customer_name: "Maria Silva",
          total_cents: 1000,
          customer_instagram: "maria",
          customer_phone: "(22) 99876-5432"
        })

      assert changeset.valid?
    end

    test "blank instagram counts as missing" do
      changeset = Order.changeset(%Order{}, Map.put(@base, :customer_instagram, ""))

      refute changeset.valid?
      assert %{customer_instagram: ["informe instagram ou WhatsApp"]} = errors_on(changeset)
    end

    test "phone is normalized to digits only" do
      changeset =
        Order.changeset(%Order{}, Map.put(@base, :customer_phone, "(22) 99876-5432"))

      assert Ecto.Changeset.get_field(changeset, :customer_phone) == "22998765432"
    end

    test "phone length is bounded" do
      assert %{customer_phone: _} =
               errors_on(Order.changeset(%Order{}, Map.put(@base, :customer_phone, "998765")))

      assert %{customer_phone: _} =
               errors_on(
                 Order.changeset(
                   %Order{},
                   Map.put(@base, :customer_phone, "551199876543210")
                 )
               )
    end
  end

  describe "normalize_phone/1" do
    test "strips formatting" do
      assert Order.normalize_phone("(22) 99876-5432") == "22998765432"
      assert Order.normalize_phone(nil) == nil
    end

    test "collapses the +55 country prefix to the local form" do
      assert Order.normalize_phone("+55 22 99876-5432") == "22998765432"
      assert Order.normalize_phone("5522998765432") == "22998765432"
    end

    test "keeps a local number whose DDD is 55" do
      # DDD 55 is Santa Maria/RS: stripping "55" here would corrupt the number.
      assert Order.normalize_phone("(55) 3222-1100") == "5532221100"
      assert Order.normalize_phone("5599998888") == "5599998888"
    end
  end

  describe "masked_name/1" do
    test "initials per word, upcased" do
      assert Order.masked_name("Maria Silva") == "M. S."
      assert Order.masked_name("joão") == "J."
      assert Order.masked_name("Ana Maria de Souza") == "A. M. D. S."
    end
  end
end
