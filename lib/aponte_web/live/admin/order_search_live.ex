defmodule AponteWeb.Admin.OrderSearchLive do
  use AponteWeb, :live_view

  alias Aponte.{Clock, Tickets}

  # ponytail: load-more grows the limit and re-queries — no offset bookkeeping,
  # no keyset cursor. Re-fetching a growing recent-list is fine at admin scale;
  # switch to keyset if the orders table ever gets big.
  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.org

    {:ok,
     assign(socket,
       term: "",
       limit: @page_size,
       results: Tickets.list_recent(org.id, @page_size),
       page_title: "Pedidos"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => term}, socket) do
    org_id = socket.assigns.org.id

    if searching?(term) do
      {:noreply, assign(socket, term: term, results: Tickets.search_orders(org_id, term))}
    else
      # cleared/short term: back to history, reset paging
      {:noreply,
       assign(socket,
         term: term,
         limit: @page_size,
         results: Tickets.list_recent(org_id, @page_size)
       )}
    end
  end

  def handle_event("load_more", _params, socket) do
    limit = socket.assigns.limit + @page_size

    {:noreply,
     assign(socket, limit: limit, results: Tickets.list_recent(socket.assigns.org.id, limit))}
  end

  defp order_url(org, id), do: url(~p"/#{org.slug}/compra/#{id}")

  # Contato do cliente na coluna: @handle quando tem instagram, senão telefone.
  defp contact_label(%{customer_instagram: ig}) when is_binary(ig), do: "@#{ig}"
  defp contact_label(%{customer_phone: phone}) when is_binary(phone), do: phone
  defp contact_label(_), do: ""

  defp searching?(term), do: String.length(String.trim(term)) >= 2

  # More to load only while the history view fills the current limit exactly.
  defp more?(term, results, limit), do: not searching?(term) and length(results) >= limit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section class="stack-4">
        <.admin_header title="Pedidos" eyebrow={@org.name} />

        <form phx-change="search">
          <input
            type="text"
            name="q"
            value={@term}
            phx-debounce="300"
            autocomplete="off"
            placeholder="@handle, nome ou telefone"
            class="input text-mono"
          />
        </form>

        <p class="text-xs text-dim">
          {if searching?(@term), do: "Resultados da busca.", else: "Pedidos mais recentes."}
        </p>

        <p :if={searching?(@term) and @results == []} class="text-sm text-dim">
          Nenhum pedido encontrado.
        </p>
        <p :if={not searching?(@term) and @results == []} class="text-sm text-dim">
          Nenhum pedido ainda.
        </p>

        <table :if={@results != []} class="data-table">
          <thead>
            <tr>
              <th>Cliente</th>
              <th>Contato</th>
              <th>Total</th>
              <th>Status</th>
              <th>Recebido</th>
              <th><span class="sr-only">Ações</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={o <- @results}>
              <td class="td-title text-cap">
                <a href={~p"/admin/#{@org.slug}/pedidos/#{o.id}"}>{o.customer_name}</a>
              </td>
              <td data-label="Contato" class="text-mono text-dim">{contact_label(o)}</td>
              <td data-label="Total" class="td-num">{money(o.total_cents)}</td>
              <td data-label="Status">
                <.status_badge status={o.status} />
              </td>
              <td data-label="Recebido" class="text-mono text-dim">
                {Clock.format(o.inserted_at, :datetime)}
              </td>
              <td class="td-actions">
                <button
                  type="button"
                  data-copy-text={order_url(@org, o.id)}
                  class="btn btn--ghost btn--sm"
                >
                  Copiar link
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <button
          :if={more?(@term, @results, @limit)}
          type="button"
          phx-click="load_more"
          class="btn btn--ghost btn--block"
        >
          Carregar mais
        </button>
      </section>
    </Layouts.admin>
    """
  end
end
