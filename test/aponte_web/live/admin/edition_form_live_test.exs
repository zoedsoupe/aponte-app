defmodule AponteWeb.Admin.EditionFormLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aponte.Editions

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    %{auth: auth}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  test "lote price accepts reais with comma and saves as cents", %{conn: conn, auth: auth} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/edicoes/nova")

    base = %{
      number: "99",
      name: "Edição Preço",
      starts_at: "2030-01-01T20:00",
      venue: "OCA ROOTS",
      accent_color: "#F07BC0"
    }

    # "+ Adicionar lote" é um JS.dispatch("change") client-side com
    # ticket_types_sort ["new"] — aqui o change é enviado direto (form/3 não
    # conhece o input de sort antes do primeiro lote existir).
    html =
      view
      |> element("#edition-form")
      |> render_change(%{edition: Map.put(base, :ticket_types_sort, ["new"])})

    assert html =~ "Preço (R$)"

    params = %{
      edition:
        Map.merge(base, %{
          ticket_types: %{
            "0" => %{
              name: "Lote 1",
              price_cents: "35,00",
              capacity: "10",
              position: "0",
              is_active: "true"
            }
          },
          ticket_types_sort: ["0"]
        })
    }

    # validate mostra o parse ("= R$ 35,00") e mantém o raw no input
    html = view |> form("#edition-form", params) |> render_change()
    assert html =~ "= R$ 35,00"
    assert html =~ ~s(value="35,00")

    assert {:error, {:live_redirect, %{to: "/admin/sesh"}}} =
             view |> form("#edition-form", params) |> render_submit()

    {:ok, org} = Aponte.Orgs.get_org_by_slug("sesh")
    edition = Enum.find(Editions.list_editions(org.id), &(&1.name == "Edição Preço"))
    assert [type] = edition.ticket_types
    assert type.price_cents == 3500
  end
end
