defmodule AponteWeb.Admin.CouponsLive do
  use AponteWeb, :live_view

  alias Aponte.{Clock, Coupons}

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.org

    {:ok,
     socket
     |> assign(:page_title, "Cupons")
     |> assign(:rules, Coupons.list_rules(org.id))
     |> assign(:coupons, Coupons.list_public_coupons(org.id))}
  end

  defp discount(%{discount_kind: :percent, discount_value: v}), do: "#{v}%"

  defp discount(%{discount_kind: :fixed, discount_value: v}),
    do: AponteWeb.CoreComponents.money(v)

  defp expiry(nil), do: "Sem expirar"
  defp expiry(exp), do: "até #{Clock.format(exp, :date)}"

  defp uses(%{max_uses: nil, uses_count: n}), do: "#{n} usos"
  defp uses(%{max_uses: max, uses_count: n}), do: "#{n}/#{max} usos"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section class="stack-5">
        <.admin_header title="Cupons" eyebrow={@org.name} />

        <section class="stack-3">
          <div class="admin-section-head">
            <div class="stack-1">
              <h2 class="section-label">Regras automáticas</h2>
              <p class="text-xs text-dim">
                Emitem um cupom pro cliente quando o pedido atinge o valor mínimo.
              </p>
            </div>
            <a href={~p"/admin/#{@org.slug}/cupons/regras/nova"} class="admin-action">
              + Nova regra
            </a>
          </div>

          <p :if={@rules == []} class="text-sm text-dim">Nenhuma regra ainda.</p>
          <table :if={@rules != []} class="data-table">
            <thead>
              <tr>
                <th>Regra</th>
                <th>Pedido mínimo</th>
                <th>Desconto</th>
                <th>Validade</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @rules}>
                <td class="td-title">
                  <a href={~p"/admin/#{@org.slug}/cupons/regras/#{r.id}"}>{r.name}</a>
                </td>
                <td data-label="Mínimo" class="td-num">
                  {AponteWeb.CoreComponents.money(r.min_order_cents)}
                </td>
                <td data-label="Desconto">{discount(r)}</td>
                <td data-label="Validade" class="text-dim">{r.expires_in_days} dias</td>
                <td data-label="Status">
                  <span :if={r.is_active} class="badge badge--published">Ativa</span>
                  <span :if={not r.is_active} class="badge badge--expired">Inativa</span>
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="stack-3">
          <div class="admin-section-head">
            <div class="stack-1">
              <h2 class="section-label">Cupons públicos</h2>
              <p class="text-xs text-dim">
                Código que qualquer cliente usa. Inscritos recebem aviso ao criar.
              </p>
            </div>
            <a href={~p"/admin/#{@org.slug}/cupons/novo"} class="admin-action admin-action--primary">
              + Novo cupom
            </a>
          </div>

          <p :if={@coupons == []} class="text-sm text-dim">Nenhum cupom público ainda.</p>
          <table :if={@coupons != []} class="data-table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Desconto</th>
                <th>Expira</th>
                <th>Usos</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={c <- @coupons}>
                <td class="td-title text-mono">
                  <a href={~p"/admin/#{@org.slug}/cupons/#{c.id}"}>{c.code}</a>
                </td>
                <td data-label="Desconto">{discount(c)}</td>
                <td data-label="Expira" class="text-dim">{expiry(c.expires_at)}</td>
                <td data-label="Usos" class="td-num">{uses(c)}</td>
                <td data-label="Status">
                  <span :if={c.is_active} class="badge badge--published">Ativo</span>
                  <span :if={not c.is_active} class="badge badge--expired">Inativo</span>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </section>
    </Layouts.admin>
    """
  end
end
