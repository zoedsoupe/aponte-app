defmodule AponteWeb.Admin.DashboardLive do
  use AponteWeb, :live_view

  alias Aponte.{Bar, Clock, Editions, Tickets}
  alias Aponte.Editions.Edition

  @topic "admin:orders"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Aponte.PubSub, @topic)

    org = socket.assigns.org
    editions = Editions.list_editions(org.id)

    {:ok, socket |> assign(editions: editions) |> select_edition(default_edition(editions))}
  end

  @impl true
  def handle_event("select_edition", %{"id" => id}, socket) do
    edition = Enum.find(socket.assigns.editions, &(&1.id == id))
    {:noreply, select_edition(socket, edition)}
  end

  @impl true
  def handle_info({event, _id}, socket) when event in [:new_order, :order_updated, :soldout] do
    {:noreply, refresh(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── data ────────────────────────────────────────────────────────────────────

  defp default_edition([]), do: nil

  defp default_edition(editions) do
    Enum.find(editions, &(&1.status == :published)) || List.first(editions)
  end

  defp select_edition(socket, nil) do
    assign(socket,
      edition: nil,
      stats: nil,
      bar: nil,
      by_type: %{},
      pending: [],
      recent: [],
      page_title: "Painel"
    )
  end

  defp select_edition(socket, %Edition{} = edition) do
    socket
    |> assign(edition: edition, page_title: "Painel — #{edition.name}")
    |> refresh()
  end

  defp refresh(%{assigns: %{edition: nil}} = socket), do: socket

  defp refresh(%{assigns: %{edition: edition, org: org}} = socket) do
    # Reload editions so a publish/status change elsewhere reflects in the selector.
    editions = Editions.list_editions(org.id)
    edition = Enum.find(editions, &(&1.id == edition.id)) || edition

    assign(socket,
      editions: editions,
      edition: edition,
      stats: Tickets.stats(edition.id),
      bar: Bar.stats(edition.id),
      by_type: Tickets.stats_by_type(edition.id),
      pending: edition_orders(Tickets.list_pending(org.id), edition.id),
      recent: edition_orders(Tickets.list_recent(org.id, 20), edition.id)
    )
  end

  # Pedidos da loja (/loja) tem edition_id nil e nao aparecem nestas listas por
  # edicao; ficam no historico global /admin/buscar e em /admin/pedidos/:id.
  defp edition_orders(orders, edition_id), do: Enum.filter(orders, &(&1.edition_id == edition_id))

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
              Avisos
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
                  {e.name} · {e.status}
                </button>
              </li>
            </ul>
          </section>
        <% end %>

        <%= if @edition do %>
          <div class="stack-5" style={"--accent: #{@edition.accent_color}"}>
            <section class="stack-3">
              <div class="admin-section-head">
                <h2 class="section-label">{@edition.name}</h2>
                <nav class="admin-quicklinks">
                  <a href={~p"/admin/#{@org.slug}/validar/#{@edition.id}"}>Porta</a>
                  <a href={~p"/admin/#{@org.slug}/balcao"}>Balcão</a>
                  <a href={~p"/admin/#{@org.slug}/edicoes/#{@edition.id}/cortesia"}>Cortesia</a>
                  <a href={~p"/admin/#{@org.slug}/tocar"}>Aplicações DJ</a>
                  <a href={~p"/admin/#{@org.slug}/cupons"}>Cupons</a>
                  <a href={~p"/admin/#{@org.slug}/produtos"}>Produtos</a>
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

            <%!-- pendências primeiro: aprovar pagamento (via DM no pedido) é o
                 fluxo principal do admin --%>
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
                      <span class="text-base text-cap">{o.customer_name}</span>
                      <span class="text-mono text-sm">{money(o.total_cents)}</span>
                    </div>
                    <div class="row space-between text-xs text-dim">
                      <span>
                        {Enum.map_join(
                          o.items,
                          " · ",
                          &"#{&1.quantity}× #{Aponte.Tickets.OrderItem.line_name(&1)}"
                        )}
                      </span>
                      <span>{Clock.format(o.inserted_at, :time)}</span>
                    </div>
                  </a>
                  <%!-- ponytail: inline onclick clipboard — LiveView-diffed rows
                        aren't re-bound by copy.js. UUID url has no quotes to escape. --%>
                  <button
                    type="button"
                    onclick={"navigator.clipboard.writeText('#{url(~p"/#{@org.slug}/compra/#{o.id}")}')"}
                    class="btn btn--ghost btn--sm btn--block"
                  >
                    Copiar link
                  </button>
                </li>
              </ul>
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
          </div>
        <% end %>
      </section>
    </Layouts.admin>
    """
  end
end
