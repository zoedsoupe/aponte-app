defmodule AponteWeb.Admin.DashboardLive do
  use AponteWeb, :live_view

  alias Aponte.{Bar, Clock, Editions, Tickets}
  alias Aponte.Editions.Edition

  @topic "admin:orders"

  # Two-tap confirm window; see OrderShowLive for rationale.
  @confirm_window_ms 8_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Aponte.PubSub, @topic)

    org = socket.assigns.org
    editions = Editions.list_editions(org.id)

    {:ok,
     socket
     |> assign(editions: editions, armed_id: nil)
     |> select_edition(default_edition(editions))}
  end

  @impl true
  def handle_event("select_edition", %{"id" => id}, socket) do
    edition = Enum.find(socket.assigns.editions, &(&1.id == id))
    {:noreply, select_edition(socket, edition)}
  end

  # Two-tap confirm straight on the pending card (the producer's main loop).
  # First tap arms this order ("tocar de novo"); the second within the window confirms.
  @impl true
  def handle_event("confirm_order", %{"id" => id}, %{assigns: %{armed_id: id}} = socket) do
    confirm_order(socket, id)
  end

  def handle_event("confirm_order", %{"id" => id}, socket) do
    Process.send_after(self(), :disarm_confirm, @confirm_window_ms)
    {:noreply, assign(socket, armed_id: id)}
  end

  @impl true
  def handle_info({event, _id}, socket) when event in [:new_order, :order_updated, :soldout] do
    {:noreply, refresh(socket)}
  end

  def handle_info(:disarm_confirm, socket), do: {:noreply, assign(socket, armed_id: nil)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp confirm_order(socket, id) do
    case Tickets.confirm_order(id) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pagamento confirmado. #{length(order.tickets)} ingresso(s).")
         |> assign(armed_id: nil)
         |> refresh()}

      {:error, :not_pending} ->
        {:noreply, flash_and_refresh(socket, "Pedido não está mais pendente.")}

      {:error, {:sold_out, _}} ->
        {:noreply, flash_and_refresh(socket, "Ingressos esgotaram antes da confirmação.")}

      {:error, {:merch_sold_out, _}} ->
        {:noreply, flash_and_refresh(socket, "Produto esgotou antes da confirmação.")}

      {:error, _} ->
        {:noreply, flash_and_refresh(socket, "Não foi possível confirmar.")}
    end
  end

  defp flash_and_refresh(socket, msg) do
    socket |> put_flash(:error, msg) |> assign(armed_id: nil) |> refresh()
  end

  # ── data ────────────────────────────────────────────────────────────────────

  defp default_edition([]), do: nil

  defp default_edition(editions) do
    Enum.find(editions, &(&1.status == :published)) || List.first(editions)
  end

  defp select_edition(socket, nil) do
    org = socket.assigns.org

    assign(socket,
      edition: nil,
      armed_id: nil,
      stats: nil,
      bar: nil,
      by_type: %{},
      edition_names: edition_names(socket.assigns.editions),
      pending: Tickets.list_pending(org.id),
      recent: Tickets.list_recent(org.id, 20),
      page_title: "Painel"
    )
  end

  defp select_edition(socket, %Edition{} = edition) do
    socket
    |> assign(edition: edition, armed_id: nil, page_title: "Painel - #{edition.name}")
    |> refresh()
  end

  # Pendentes e histórico são org-wide (pedidos da loja, sem edição, também
  # aparecem); stats/lotes/balcão seguem filtrados pela edição selecionada.
  defp refresh(%{assigns: %{edition: nil, org: org}} = socket) do
    editions = Editions.list_editions(org.id)

    assign(socket,
      editions: editions,
      edition_names: edition_names(editions),
      pending: Tickets.list_pending(org.id),
      recent: Tickets.list_recent(org.id, 20)
    )
  end

  defp refresh(%{assigns: %{edition: edition, org: org}} = socket) do
    # Reload editions so a publish/status change elsewhere reflects in the selector.
    editions = Editions.list_editions(org.id)
    edition = Enum.find(editions, &(&1.id == edition.id)) || edition

    assign(socket,
      editions: editions,
      edition: edition,
      edition_names: edition_names(editions),
      stats: Tickets.stats(edition.id),
      bar: Bar.stats(edition.id),
      by_type: Tickets.stats_by_type(edition.id),
      pending: Tickets.list_pending(org.id),
      recent: Tickets.list_recent(org.id, 20)
    )
  end

  defp edition_names(editions), do: Map.new(editions, &{&1.id, &1.name})

  defp edition_tag(_names, nil), do: "loja"
  defp edition_tag(names, id), do: Map.get(names, id, "edição removida")

  # Contato do cliente na linha: @handle quando tem instagram, senão telefone.
  defp contact_label(%{customer_instagram: ig}) when is_binary(ig), do: "@#{ig}"
  defp contact_label(%{customer_phone: phone}) when is_binary(phone), do: phone
  defp contact_label(_), do: nil

  # Relative age on pending rows: confirm-or-cancel depends on how stale a hold
  # is ("did they just pay?"), which a raw clock time hides.
  defp age_label(inserted_at) do
    minutes = DateTime.diff(Clock.now_utc(), Clock.to_brt(inserted_at), :minute)

    cond do
      minutes < 1 -> "agora"
      minutes < 60 -> "há #{minutes} min"
      minutes < 1440 -> "há #{div(minutes, 60)} h"
      true -> "há #{div(minutes, 1440)} d"
    end
  end

  defp lote_stats(by_type, type) do
    s = Map.get(by_type, type.id, %{held: 0, sold: 0, validated: 0})
    Map.merge(s, %{capacity: type.capacity, available: type.available})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]}>
      <section class="stack-5">
        <.admin_header title="Painel" eyebrow={@org.name}>
          <:actions>
            <button
              type="button"
              data-push-toggle
              data-push-vapid-url={~p"/admin/#{@org.slug}/push/vapid-key"}
              data-push-sub-url={~p"/admin/#{@org.slug}/push/subscribe"}
              class="btn btn--ghost btn--sm"
            >
              Notificações de pedidos
            </button>
            <a href={~p"/admin/#{@org.slug}/edicoes/nova"} class="admin-action admin-action--primary">
              + Nova edição
            </a>
          </:actions>
        </.admin_header>

        <div :if={@editions == []} class="empty-cta stack-3">
          <p class="text-sm text-dim">
            Nenhuma edição ainda. O painel ganha vida quando você criar a primeira.
          </p>
          <div class="admin-actions">
            <a href={~p"/admin/#{@org.slug}/edicoes/nova"} class="admin-action admin-action--primary">
              Criar a primeira edição
            </a>
            <a href={~p"/admin/#{@org.slug}/produtos"} class="admin-action">Produtos</a>
            <a href={~p"/admin/#{@org.slug}/cupons"} class="admin-action">Cupons</a>
          </div>
        </div>

        <%= if @editions != [] do %>
          <section class="stack-2">
            <h2 class="section-label">Edição</h2>
            <ul class="row gap-2" style="flex-wrap: wrap;">
              <li :for={e <- @editions}>
                <button
                  type="button"
                  phx-click="select_edition"
                  phx-value-id={e.id}
                  class={["chip", @edition && e.id == @edition.id && "chip--active"]}
                >
                  {e.name} · {status_label(e.status)}
                </button>
              </li>
            </ul>
          </section>
        <% end %>

        <%!-- pendências primeiro: aprovar pagamento (via DM no pedido) é o
             fluxo principal do admin. Org-wide de propósito: pedido da loja
             (sem edição) também é pendência a aprovar. --%>
        <section class="stack-3">
          <div class="admin-section-head">
            <h2 class="section-label">Pendentes ({length(@pending)})</h2>
            <a href={~p"/admin/#{@org.slug}/buscar"} class="text-xs text-accent">
              Todos os pedidos
            </a>
          </div>
          <p :if={@pending == []} class="text-sm text-dim">Nenhum pedido pendente.</p>
          <ul class="stack-2">
            <li :for={o <- @pending} class="card stack-2">
              <a href={~p"/admin/#{@org.slug}/pedidos/#{o.id}"} class="stack-1 block">
                <div class="row space-between">
                  <span class="text-base text-cap">
                    {o.customer_name}
                    <span :if={contact_label(o)} class="text-xs text-dim text-mono">
                      {contact_label(o)}
                    </span>
                  </span>
                  <span class="text-mono text-sm">{money(o.total_cents)}</span>
                </div>
                <div class="row gap-2 align-center text-xs text-dim">
                  <span class="chip">{edition_tag(@edition_names, o.edition_id)}</span>
                  <span class="flex-1">
                    {Enum.map_join(
                      o.items,
                      " · ",
                      &"#{&1.quantity}× #{Aponte.Tickets.OrderItem.line_name(&1)}"
                    )}
                  </span>
                  <span>{age_label(o.inserted_at)}</span>
                </div>
              </a>
              <div class="row gap-2">
                <button
                  type="button"
                  phx-click="confirm_order"
                  phx-value-id={o.id}
                  class={["btn btn--sm flex-1", @armed_id == o.id && "btn--primary"]}
                >
                  {if @armed_id == o.id,
                    do: "Tocar de novo: #{money(o.total_cents)}",
                    else: "Confirmar pagamento"}
                </button>
                <button
                  type="button"
                  data-copy-text={url(~p"/#{@org.slug}/compra/#{o.id}")}
                  class="btn btn--ghost btn--sm"
                >
                  Copiar link
                </button>
              </div>
            </li>
          </ul>
        </section>

        <%= if @edition do %>
          <div class="stack-5" style={"--accent: #{@edition.accent_color}"}>
            <section class="stack-3">
              <div class="admin-section-head">
                <h2 class="section-label">{@edition.name}</h2>
                <%!-- só links que exigem a edição na URL; o resto vive na
                     tab bar (Produtos, Porta, Balcão) e no header (Cupons, DJ). --%>
                <nav class="admin-quicklinks" aria-label="Ações da edição">
                  <a href={~p"/admin/#{@org.slug}/edicoes/#{@edition.id}/cortesia"}>Cortesia</a>
                  <a href={~p"/admin/#{@org.slug}/edicoes/#{@edition.id}"}>Editar</a>
                </nav>
              </div>

              <div class="stack-1">
                <span class="section-label">Receita confirmada</span>
                <span class="text-mono text-2xl text-accent">{money(@stats.revenue_cents)}</span>
              </div>

              <div class="stat-grid">
                <.stat_card label="Capacidade" value={@stats.capacity} />
                <.stat_card label="Vendido" value={@stats.sold_confirmed} />
                <.stat_card label="Pendente" value={@stats.held_pending} />
                <.stat_card label="Disponível" value={@stats.available} />
                <.stat_card label="Validados" value={@stats.validated} />
              </div>
            </section>

            <section :if={@bar && @bar.count > 0} class="stack-3">
              <div class="admin-section-head">
                <h2 class="section-label">Balcão ({@bar.count} vendas)</h2>
                <span class="text-mono text-lg text-accent">{money(@bar.total_cents)}</span>
              </div>
              <div class="stat-grid">
                <.stat_card label="Dinheiro" value={money(@bar.cash_cents)} />
                <.stat_card label="PIX" value={money(@bar.pix_cents)} />
              </div>
              <ul :if={@bar.top_items != []} class="stack-1">
                <li :for={t <- @bar.top_items} class="row space-between text-xs text-dim">
                  <span>{t.qty}× {t.name}</span>
                  <span class="text-mono">{money(t.cents)}</span>
                </li>
              </ul>
            </section>

            <section :if={@edition.ticket_types != []} class="stack-3">
              <h2 class="section-label">Lotes</h2>
              <table class="data-table">
                <thead>
                  <tr>
                    <th>Lote</th>
                    <th>Cap</th>
                    <th>Vend</th>
                    <th>Pend</th>
                    <th>Disp</th>
                    <th>Valid</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={type <- @edition.ticket_types}>
                    <% s = lote_stats(@by_type, type) %>
                    <td class="td-title">{type.name}</td>
                    <td data-label="Cap" class="td-num">{s.capacity}</td>
                    <td data-label="Vend" class="td-num">{s.sold}</td>
                    <td data-label="Pend" class="td-num">{s.held}</td>
                    <td data-label="Disp" class="td-num">{s.available}</td>
                    <td data-label="Valid" class="td-num">{s.validated}</td>
                  </tr>
                </tbody>
              </table>
            </section>
          </div>
        <% end %>

        <section :if={@recent != []} class="stack-3">
          <h2 class="section-label">Histórico</h2>
          <ul class="inset-list">
            <li :for={o <- @recent}>
              <a href={~p"/admin/#{@org.slug}/pedidos/#{o.id}"} class="inset-row">
                <span class="text-base text-cap">{o.customer_name}</span>
                <span class="row gap-2 align-center">
                  <span class="text-mono text-xs text-dim">
                    {money(o.total_cents)} · {Clock.format(o.inserted_at, :time)}
                  </span>
                  <.status_badge status={o.status} />
                </span>
              </a>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.admin>
    """
  end
end
