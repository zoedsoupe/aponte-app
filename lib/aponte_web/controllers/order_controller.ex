defmodule AponteWeb.OrderController do
  use AponteWeb, :controller

  alias Aponte.{Clock, Coupons, Editions, Merch, Tickets}
  alias Aponte.Editions.{Edition, TicketType}
  alias Aponte.Tickets.Order
  alias Aponte.Payments.Pix
  alias AponteWeb.Plugs

  def new(conn, _params) do
    org = conn.assigns.org

    case Editions.current_edition(org.id) do
      %Edition{} = edition ->
        render_form(conn, edition, Order.changeset(%Order{}, %{}), %{})

      _ ->
        conn
        |> put_flash(:error, "Nenhuma edição com ingressos à venda agora.")
        |> redirect(to: ~p"/#{org.slug}")
    end
  end

  def create(conn, params) do
    org = conn.assigns.org
    order_params = Map.get(params, "order", %{})
    items_params = Map.get(params, "items", %{})
    merch_params = Map.get(params, "merch", %{})

    case Editions.current_edition(org.id) do
      %Edition{} = edition ->
        case Tickets.create_order(
               org,
               build_attrs(edition, order_params, items_params, merch_params)
             ) do
          {:ok, order} ->
            redirect(conn, to: ~p"/#{org.slug}/compra/#{order.id}")

          {:error, {:sold_out, type_id}} ->
            type = Editions.get_ticket_type!(type_id)

            conn
            |> put_flash(:error, "Ingressos esgotados para #{type.name}.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:not_on_sale, _id}} ->
            conn
            |> put_flash(:error, "Esse lote não está mais à venda.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, :empty_cart} ->
            conn
            |> put_flash(:error, "Escolha pelo menos um ingresso.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:unknown_merch_item, _id}} ->
            conn
            |> put_flash(:error, "Produto indisponível.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:merch_unavailable, _id}} ->
            conn
            |> put_flash(:error, "Produto indisponível.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:merch_sold_out, _id}} ->
            conn
            |> put_flash(:error, "Produto esgotado.")
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, {:coupon, reason}} ->
            conn
            |> put_flash(:error, coupon_error(reason))
            |> render_form(reload(edition), changeset(order_params), items_params)

          {:error, %Ecto.Changeset{} = cs} ->
            render_form(conn, reload(edition), %{cs | action: :insert}, items_params)

          {:error, _} ->
            conn
            |> put_flash(:error, "Não foi possível registrar o pedido.")
            |> render_form(reload(edition), changeset(order_params), items_params)
        end

      _ ->
        conn
        |> put_flash(:error, "Nenhuma edição com ingressos à venda agora.")
        |> redirect(to: ~p"/#{org.slug}")
    end
  end

  def show(conn, %{"id" => id}) do
    org = conn.assigns.org
    order = Tickets.get_order!(id)

    # Orders are capability URLs, but the tenant boundary still holds: an
    # order only renders under its own org's slug.
    if order.org_id == org.id do
      edition = order.edition_id && Editions.get_edition!(order.edition_id)

      conn
      |> Plugs.Accent.assign_edition_accent(edition)
      |> assign(:no_index, true)
      |> render(:show,
        org: org,
        order: order,
        edition: edition,
        pix: pix_payload(order),
        earned: Coupons.earned_for_order(order.id),
        page_title: "Ingresso"
      )
    else
      not_found(conn)
    end
  end

  # Static shell — the list is rendered client-side from localStorage
  # (assets/js/orders.js). The lookup form posts to :lookup.
  def history(conn, _params) do
    conn
    |> assign(:no_index, true)
    |> render(:history, org: conn.assigns.org, page_title: "Meus ingressos")
  end

  # Buyer self-lookup: phone + order code. A miss reveals nothing about which
  # field failed (generic "nada encontrado").
  def lookup(conn, params) do
    org = conn.assigns.org

    order =
      case Tickets.lookup_order(org.id, params["phone"] || "", params["code"] || "") do
        {:ok, order} -> order
        {:error, :not_found} -> nil
      end

    conn
    |> assign(:no_index, true)
    |> render(:lookup, org: org, order: order, page_title: "Meus ingressos")
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp reload(%Edition{id: id}), do: Editions.get_edition!(id)

  defp changeset(order_params), do: Order.changeset(%Order{}, order_params)

  defp render_form(conn, edition, changeset, items) do
    conn
    |> Plugs.Accent.assign_edition_accent(edition)
    |> render(:new,
      org: conn.assigns.org,
      edition: edition,
      changeset: changeset,
      lots: lots_on_sale(edition),
      merch: Merch.list_featured_items(edition.id),
      items: normalize_items_param(items),
      page_title: "Comprar — #{edition.name}"
    )
  end

  defp lots_on_sale(%Edition{ticket_types: types}) do
    now = Clock.now_utc()

    types
    |> Enum.filter(&(TicketType.on_sale?(&1, now) and &1.available > 0))
    |> Enum.sort_by(& &1.position)
  end

  defp build_attrs(edition, order_params, items_params, merch_params) do
    ticket_lines =
      items_params
      |> Enum.map(fn {type_id, qty} -> %{ticket_type_id: type_id, quantity: qty} end)
      |> Enum.reject(&(&1.quantity in ["", "0", 0, nil]))

    merch_lines =
      merch_params
      |> Enum.map(fn {item_id, qty} -> %{merch_item_id: item_id, quantity: qty} end)
      |> Enum.reject(&(&1.quantity in ["", "0", 0, nil]))

    order_params
    |> Map.put("edition_id", edition.id)
    |> Map.put("items", ticket_lines ++ merch_lines)
    |> Map.put("status", "pending")
  end

  defp normalize_items_param(items) when is_map(items), do: items
  defp normalize_items_param(_), do: %{}

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_root_layout(false)
    |> put_view(AponteWeb.ErrorHTML)
    |> render("404.html")
    |> halt()
  end

  defp coupon_error(:not_found), do: "Cupom não encontrado."
  defp coupon_error(:expired), do: "Esse cupom expirou."
  defp coupon_error(:used), do: "Esse cupom já foi usado."
  defp coupon_error(:inactive), do: "Esse cupom não está mais ativo."
  defp coupon_error(:exhausted), do: "Esse cupom atingiu o limite de usos."
  defp coupon_error(:wrong_customer), do: "Esse cupom é de outra pessoa."
  defp coupon_error(:coupon_taken), do: "Esse cupom acabou de ser usado. tente outro."

  defp coupon_error({:min_order, cents}),
    do: "Esse cupom exige pedido mínimo de #{AponteWeb.CoreComponents.money(cents)}."

  defp coupon_error(_), do: "Cupom inválido."

  defp pix_payload(%Order{status: :pending} = order) do
    cfg = Application.fetch_env!(:aponte, :pix)

    emv =
      Pix.build(
        pix_key: order.pix_key || cfg[:key],
        amount_cents: order.total_cents,
        merchant_name: cfg[:merchant_name],
        merchant_city: cfg[:merchant_city],
        txid: order.id |> String.replace("-", "") |> String.slice(0, 25)
      )

    %{emv: emv, svg: Pix.to_svg(emv)}
  end

  defp pix_payload(_), do: nil
end
