defmodule AponteWeb.Admin.ProductsLive do
  use AponteWeb, :live_view

  alias Aponte.Merch

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.org

    {:ok, assign(socket, items: Merch.list_items(org.id), page_title: "Produtos")}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    item = Merch.get_item!(id)
    {:ok, _} = Merch.toggle_active(item)
    {:noreply, assign(socket, items: Merch.list_items(socket.assigns.org.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section class="stack-5">
        <.admin_header title="Produtos" eyebrow={@org.name}>
          <:actions>
            <a href={~p"/admin/#{@org.slug}/produtos/novo"} class="admin-action admin-action--primary">
              + Novo
            </a>
          </:actions>
        </.admin_header>

        <p :if={@items == []} class="text-sm text-dim">Nenhum produto ainda.</p>

        <table :if={@items != []} class="data-table">
          <thead>
            <tr>
              <th>Produto</th>
              <th>Preço</th>
              <th>Estoque</th>
              <th>Tipo</th>
              <th>Status</th>
              <th><span class="sr-only">Ações</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={item <- @items}>
              <td class="td-title">
                <a href={~p"/admin/#{@org.slug}/produtos/#{item.id}"}>{item.name}</a>
              </td>
              <td data-label="Preço" class="td-num">{money(item.price_cents)}</td>
              <td data-label="Estoque" class="td-num">{stock_label(item)}</td>
              <td data-label="Tipo">
                <span class="chip">{if item.kind == :counter, do: "balcão", else: "loja"}</span>
              </td>
              <td data-label="Status">
                <span :if={item.is_active} class="badge badge--published">Ativo</span>
                <span :if={not item.is_active} class="badge badge--expired">Inativo</span>
              </td>
              <td class="td-actions">
                <button
                  type="button"
                  phx-click="toggle"
                  phx-value-id={item.id}
                  class="btn btn--ghost btn--sm"
                >
                  {if item.is_active, do: "Desativar", else: "Ativar"}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.admin>
    """
  end

  defp stock_label(%{track_stock: false}), do: "livre"
  defp stock_label(item), do: "#{item.available}/#{item.stock}"
end
