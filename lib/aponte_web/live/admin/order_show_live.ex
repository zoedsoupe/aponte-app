defmodule AponteWeb.Admin.OrderShowLive do
  use AponteWeb, :live_view

  alias Aponte.{Clock, Tickets}
  alias Aponte.Tickets.Ticket
  alias Aponte.Merch.Unit
  alias AponteWeb.Instagram

  @topic "admin:orders"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns.org

    # Guarda contra URL-tampering cross-org: o pedido precisa ser da org da URL.
    case Tickets.get_order_in_org(org.id, id) do
      {:ok, order} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Aponte.PubSub, @topic)
        {:ok, assign(socket, order: order, page_title: "Pedido")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Pedido não encontrado.")
         |> redirect(to: ~p"/admin/#{org.slug}/buscar")}
    end
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    case Tickets.confirm_order(socket.assigns.order.id) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Pagamento confirmado. #{length(order.tickets)} ingresso(s) emitido(s)."
         )
         |> assign(order: order)}

      {:error, :not_pending} ->
        {:noreply,
         socket
         |> put_flash(:error, "Pedido não está mais pendente (foi cancelado ou já confirmado).")
         |> reload()}

      {:error, {:sold_out, _id}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Ingressos esgotaram antes da confirmação. Pedido segue pendente.")
         |> reload()}

      {:error, {:merch_sold_out, _id}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Produto esgotou antes da confirmação. Pedido segue pendente.")
         |> reload()}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Não foi possível confirmar.") |> reload()}
    end
  end

  def handle_event("cancel", _params, socket) do
    case Tickets.cancel_order(socket.assigns.order.id) do
      {:ok, order} ->
        {:noreply, socket |> put_flash(:info, "Pedido cancelado.") |> assign(order: order)}

      {:error, :not_cancellable} ->
        {:noreply, socket |> put_flash(:error, "Esse pedido não pode ser cancelado.") |> reload()}
    end
  end

  @impl true
  def handle_info({event, id}, %{assigns: %{order: %{id: id}}} = socket)
      when event in [:order_updated, :new_order, :soldout] do
    {:noreply, reload(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload(socket), do: assign(socket, order: Tickets.get_order!(socket.assigns.order.id))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Pedidos" back_to={~p"/admin/#{@org.slug}/buscar"}>
      <section class="stack-5">
        <header class="stack-2">
          <p class="eyebrow">Pedido</p>
          <h1 class="text-xl">{@order.customer_name}</h1>
          <div class="row gap-2 align-center">
            <.status_badge status={@order.status} />
            <span class="text-mono text-sm text-dim">@{@order.customer_instagram}</span>
          </div>
        </header>

        <%!-- DM é o canal admin↔cliente (aprovação de pagamento async no
             Instagram): primeiro botão, sempre visível, qualquer status. --%>
        <div class="order-actions">
          <a
            href={Instagram.dm_url(@order.customer_instagram)}
            target="_blank"
            rel="noopener"
            class="btn btn--primary"
          >
            Abrir DM
          </a>
          <.button :if={@order.status == :pending} phx-click="confirm" variant={:accent}>
            Confirmar pagamento
          </.button>
        </div>

        <.button
          :if={@order.status == :pending}
          phx-click="cancel"
          data-confirm="Cancelar e devolver capacidade?"
          variant={:danger}
          class="btn--block"
        >
          Cancelar pedido
        </.button>

        <.button
          :if={@order.status == :confirmed}
          phx-click="cancel"
          data-confirm="Cancelar pedido confirmado? Isso apaga os ingressos e produtos emitidos."
          variant={:danger}
          class="btn--block"
        >
          Cancelar pedido
        </.button>

        <.form_section title="Itens">
          <ul class="stack-2">
            <li :for={item <- @order.items} class="row space-between text-sm">
              <span>{item.quantity}x {Aponte.Tickets.OrderItem.line_name(item)}</span>
              <span class="text-mono">{money(item.unit_price_cents * item.quantity)}</span>
            </li>
          </ul>

          <div :if={@order.discount_cents > 0} class="row space-between text-sm text-accent">
            <span>Cupom {@order.coupon_code}</span>
            <span class="text-mono">- {money(@order.discount_cents)}</span>
          </div>

          <div class="row space-between total-line">
            <span class="text-sm text-muted">Total</span>
            <span class="text-mono text-lg">{money(@order.total_cents)}</span>
          </div>

          <p class="text-xs text-dim">
            Recebido <span class="text-mono">{Clock.format(@order.inserted_at, :datetime)}</span>
          </p>
        </.form_section>

        <.form_section :if={@order.tickets != []} title={"Ingressos emitidos (#{length(@order.tickets)})"}>
          <ul class="inset-list">
            <li :for={t <- @order.tickets} class="inset-row inset-row--static">
              <span class="text-mono">{Ticket.display_code(t)}</span>
              <span :if={t.used_at} class="text-xs text-dim">
                Validado {Clock.format(t.used_at, :time)}
              </span>
              <span :if={is_nil(t.used_at)} class="text-xs text-dim">Não usado</span>
            </li>
          </ul>
        </.form_section>

        <.form_section :if={@order.merch_units != []} title={"Produtos emitidos (#{length(@order.merch_units)})"}>
          <ul class="inset-list">
            <li :for={u <- @order.merch_units} class="inset-row inset-row--static">
              <span>
                <span class="text-mono">{Unit.display_code(u)}</span> · {u.merch_item_name_snapshot}
              </span>
              <span :if={u.redeemed_at} class="text-xs text-dim">
                Retirado {Clock.format(u.redeemed_at, :time)}
              </span>
              <span :if={is_nil(u.redeemed_at)} class="text-xs text-dim">Não retirado</span>
            </li>
          </ul>
        </.form_section>

        <details class="stack-2">
          <summary class="text-sm text-muted">Link do pedido / perfil</summary>
          <div class="stack-2">
            <p id="order-link" class="text-mono text-xs break-all">
              {url(~p"/#{@org.slug}/compra/#{@order.id}")}
            </p>
            <button type="button" data-copy-target="#order-link" class="btn btn--ghost btn--block">
              Copiar link
            </button>
            <a
              href={Instagram.profile_url(@order.customer_instagram)}
              target="_blank"
              rel="noopener"
              class="btn btn--ghost btn--block"
            >
              Ver perfil
            </a>
          </div>
        </details>
      </section>
    </Layouts.admin>
    """
  end
end
