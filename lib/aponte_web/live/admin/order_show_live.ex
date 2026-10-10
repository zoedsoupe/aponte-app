defmodule AponteWeb.Admin.OrderShowLive do
  use AponteWeb, :live_view

  alias Aponte.{Clock, Tickets}
  alias Aponte.Tickets.{OrderItem, Ticket}
  alias Aponte.Merch.Unit
  alias AponteWeb.Instagram

  @topic "admin:orders"

  # Two-tap confirm window. Generous enough to survive a slow longpoll round-trip
  # (a dropped/re-armed tap used to leave the order silently pending).
  @confirm_window_ms 8_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = socket.assigns.org

    # Guarda contra URL-tampering cross-org: o pedido precisa ser da org da URL.
    case Tickets.get_order_in_org(org.id, id) do
      {:ok, order} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Aponte.PubSub, @topic)
        {:ok, assign(socket, order: order, confirm_armed: false, page_title: "Pedido")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Pedido não encontrado.")
         |> redirect(to: ~p"/admin/#{org.slug}/buscar")}
    end
  end

  @impl true
  # Dois toques pra confirmar (S2): o primeiro arma ("tocar de novo"), o
  # segundo dentro da janela confirma de fato. Sem JS: assign + send_after.
  def handle_event("confirm", _params, %{assigns: %{confirm_armed: false}} = socket) do
    Process.send_after(self(), :disarm_confirm, @confirm_window_ms)
    {:noreply, assign(socket, confirm_armed: true)}
  end

  def handle_event("confirm", _params, socket) do
    case Tickets.confirm_order(socket.assigns.order.id) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Pagamento confirmado. #{length(order.tickets)} ingresso(s) emitido(s)."
         )
         |> assign(order: order, confirm_armed: false)}

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
  def handle_info(:disarm_confirm, socket), do: {:noreply, assign(socket, confirm_armed: false)}

  def handle_info({event, id}, %{assigns: %{order: %{id: id}}} = socket)
      when event in [:order_updated, :new_order, :soldout] do
    {:noreply, reload(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload(socket),
    do: assign(socket, order: Tickets.get_order!(socket.assigns.order.id), confirm_armed: false)

  # Brazilian numbers come in as DDD + número (10–11 dígitos); prepend country
  # code for the wa.me deep-link unless it's already there.
  defp wa_url(digits) when is_binary(digits) do
    full = if String.length(digits) <= 11, do: "55" <> digits, else: digits
    "https://wa.me/" <> full
  end

  # Rótulo do segundo toque: quantos ingressos o pedido vai emitir (pedido só
  # de merch mostra itens, não ingressos).
  defp confirm_summary(order) do
    tickets = order.items |> Enum.filter(&OrderItem.ticket?/1) |> Enum.sum_by(& &1.quantity)

    if tickets > 0 do
      "#{tickets} ingressos"
    else
      "#{Enum.sum_by(order.items, & &1.quantity)} itens"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      org={@org}
      current_path={assigns[:admin_path]}
      back="Pedidos"
      back_to={~p"/admin/#{@org.slug}/buscar"}
    >
      <section class="stack-5">
        <header class="stack-2">
          <p class="eyebrow">Pedido</p>
          <h1 class="text-xl">{@order.customer_name}</h1>
          <div class="row gap-2 align-center">
            <.status_badge status={@order.status} />
            <span :if={@order.customer_instagram} class="text-mono text-sm text-dim">
              @{@order.customer_instagram}
            </span>
            <span
              :if={is_nil(@order.customer_instagram) and @order.customer_phone}
              class="text-mono text-sm text-dim"
            >
              {@order.customer_phone}
            </span>
          </div>
        </header>

        <%!-- DM é o canal admin↔cliente (aprovação de pagamento async no
             Instagram): primeiro botão, sempre visível, qualquer status.
             Comprador sem instagram recebe WhatsApp (wa.me) no lugar, com o
             número à vista pra copiar. --%>
        <div class="order-actions">
          <a
            :if={@order.customer_instagram}
            href={Instagram.dm_url(@order.customer_instagram)}
            target="_blank"
            rel="noopener"
            class="btn btn--primary"
          >
            Abrir DM
          </a>
          <a
            :if={@order.customer_phone}
            href={wa_url(@order.customer_phone)}
            target="_blank"
            rel="noopener"
            class="btn btn--primary"
          >
            Abrir WhatsApp
          </a>
          <.button :if={@order.status == :pending} phx-click="confirm" variant={:accent}>
            {if @confirm_armed,
              do:
                "Tocar de novo pra confirmar #{money(@order.total_cents)} · #{confirm_summary(@order)}",
              else: "Confirmar pagamento"}
          </.button>
        </div>

        <p :if={@order.customer_phone} class="text-mono text-sm text-dim">
          {@order.customer_phone}
        </p>

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

        <.form_section
          :if={@order.tickets != []}
          title={"Ingressos emitidos (#{length(@order.tickets)})"}
        >
          <ul class="inset-list">
            <li :for={t <- @order.tickets} class="inset-row inset-row--static">
              <span class="text-mono">{Ticket.display_code(t)}</span>
              <span :if={t.used_at} class="text-xs text-dim">
                Validado {Clock.format(t.used_at, :time)}
              </span>
              <span :if={is_nil(t.used_at)} class="text-xs text-dim">Não usado</span>
            </li>
          </ul>
          <a
            :if={@order.edition_id}
            href={~p"/admin/#{@org.slug}/validar/#{@order.edition_id}"}
            class="btn btn--ghost btn--block"
          >
            Validar na porta
          </a>
        </.form_section>

        <.form_section
          :if={@order.merch_units != []}
          title={"Produtos emitidos (#{length(@order.merch_units)})"}
        >
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
              :if={@order.customer_instagram}
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
