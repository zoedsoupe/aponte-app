defmodule AponteWeb.Admin.CortesiaLive do
  use AponteWeb, :live_view

  alias Aponte.{Editions, Tickets}

  @impl true
  def mount(%{"id" => edition_id}, _session, socket) do
    org = socket.assigns.org

    # Guarda contra URL-tampering cross-org: a edição precisa ser da org da URL.
    case Editions.get_edition_in_org(org.id, edition_id) do
      {:ok, edition} ->
        comp_lotes = Enum.filter(edition.ticket_types, &(not &1.is_active))

        {:ok,
         assign(socket,
           edition: edition,
           comp_lotes: comp_lotes,
           page_title: "Cortesia — #{edition.name}",
           emitted: nil,
           form: new_form()
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Edição não encontrada.")
         |> redirect(to: ~p"/admin/#{org.slug}")}
    end
  end

  @impl true
  def handle_event("emit", %{"comp" => params}, socket) do
    case parse_quantity(params["quantity"]) do
      {:ok, qty} ->
        input = %{
          org_id: socket.assigns.edition.org_id,
          edition_id: socket.assigns.edition.id,
          ticket_type_id: params["ticket_type_id"],
          customer_name: params["customer_name"],
          customer_instagram: params["customer_instagram"],
          quantity: qty
        }

        emit(socket, input)

      :error ->
        {:noreply, put_flash(socket, :error, "Quantidade precisa ser maior que zero.")}
    end
  end

  defp emit(socket, input) do
    case Tickets.issue_confirmed(input, notify?: true) do
      {:ok, %{order: order, codes: codes}} ->
        {:noreply,
         socket
         |> assign(
           emitted: %{
             order_id: order.id,
             url: order_url(socket.assigns.org, order.id),
             codes: codes
           },
           form: new_form()
         )
         |> put_flash(:info, "#{length(codes)} cortesia(s) emitida(s).")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form: to_form(cs, as: :comp))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não deu pra emitir. confere o lote.")}
    end
  end

  defp parse_quantity(raw) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp new_form do
    to_form(
      %{
        "customer_name" => "",
        "customer_instagram" => "",
        "quantity" => "1",
        "ticket_type_id" => ""
      },
      as: :comp
    )
  end

  defp order_url(org, id), do: AponteWeb.Endpoint.url() <> "/#{org.slug}/compra/#{id}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section class="stack-5">
        <.admin_header title="Cortesia" eyebrow={@edition.name} />
        <p class="text-xs text-dim">
          Emite ingressos confirmados num lote de cortesia, sem consumir capacidade paga.
        </p>

        <p :if={@comp_lotes == []} class="text-sm text-dim">
          Nenhum lote de cortesia. crie um lote inativo na edição primeiro.
          <a href={~p"/admin/#{@org.slug}/edicoes/#{@edition.id}"} class="text-accent">
            Editar edição →
          </a>
        </p>

        <.form
          :if={@comp_lotes != []}
          for={@form}
          phx-submit="emit"
          class="stack-5"
          id="cortesia-form"
        >
          <.form_section title="Convidado(a)">
            <.input field={@form[:customer_name]} label="Nome" autocomplete="off" />
            <.input field={@form[:customer_instagram]} label="Instagram (sem @)" autocomplete="off" />
          </.form_section>

          <.form_section title="Ingressos">
            <div class="field-row">
              <.input
                field={@form[:quantity]}
                type="number"
                label="Quantidade"
                min="1"
                inputmode="numeric"
              />
              <.input
                field={@form[:ticket_type_id]}
                type="select"
                label="Lote de cortesia"
                options={Enum.map(@comp_lotes, &{&1.name, &1.id})}
              />
            </div>
          </.form_section>

          <.form_bar>
            <.button type="submit" class="btn--block">Emitir cortesia</.button>
          </.form_bar>
        </.form>

        <div :if={@emitted} class="card stack-2">
          <h2 class="section-label">Emitido</h2>
          <a href={@emitted.url} target="_blank" rel="noopener" class="text-accent text-mono text-sm">
            {@emitted.url}
          </a>
          <ul class="stack-1">
            <li :for={code <- @emitted.codes}>
              <code class="text-mono">{code}</code>
            </li>
          </ul>
          <button
            type="button"
            onclick={"navigator.clipboard.writeText('#{@emitted.url}')"}
            class="btn btn--ghost btn--sm btn--block"
          >
            Copiar link
          </button>
        </div>
      </section>
    </Layouts.admin>
    """
  end
end
