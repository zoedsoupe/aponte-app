defmodule AponteWeb.Admin.CouponFormLive do
  use AponteWeb, :live_view

  alias Aponte.{Clock, Coupons}
  alias Aponte.Coupons.Coupon

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_coupon(socket, params, socket.assigns.live_action)}
  end

  @impl true
  def handle_event("validate", %{"coupon" => params}, socket) do
    changeset =
      socket.assigns.coupon
      |> Coupons.change_public_coupon(blank_to_nil(params))
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, form: to_form(changeset), expires_in_days: params["expires_in_days"])}
  end

  def handle_event("save", %{"coupon" => params}, %{assigns: %{live_action: :new}} = socket) do
    org = socket.assigns.org
    attrs = params |> blank_to_nil() |> put_expires_at()

    case Coupons.create_public_coupon(org, attrs) do
      {:ok, coupon} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cupom #{coupon.code} criado.")
         |> push_navigate(to: ~p"/admin/#{org.slug}/cupons")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"coupon" => params}, socket) do
    attrs = params |> blank_to_nil() |> put_expires_at()

    case Coupons.update_public_coupon(socket.assigns.coupon, attrs) do
      {:ok, _coupon} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cupom salvo.")
         |> push_navigate(to: ~p"/admin/#{socket.assigns.org.slug}/cupons")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Coupons.delete_coupon(socket.assigns.coupon)

    {:noreply,
     socket
     |> put_flash(:info, "Cupom removido.")
     |> push_navigate(to: ~p"/admin/#{socket.assigns.org.slug}/cupons")}
  end

  defp assign_coupon(socket, _params, :new), do: assign_form(socket, %Coupon{is_active: true})

  defp assign_coupon(socket, %{"id" => id}, :edit) do
    org = socket.assigns.org

    case Coupons.fetch_coupon(id) do
      # Guarda contra URL-tampering cross-org: o cupom precisa ser da org da URL.
      {:ok, %Coupon{org_id: org_id} = coupon} when org_id == org.id ->
        assign_form(socket, coupon)

      _ ->
        socket
        |> put_flash(:error, "Cupom não encontrado.")
        |> redirect(to: ~p"/admin/#{org.slug}")
    end
  end

  defp assign_form(socket, coupon) do
    assign(socket,
      coupon: coupon,
      page_title: if(coupon.id, do: "Editar cupom", else: "Novo cupom"),
      expires_in_days: "",
      form: to_form(Coupons.change_public_coupon(coupon))
    )
  end

  # Empty optional number/text inputs arrive as "" — drop them so they cast to
  # nil instead of failing integer validation.
  defp blank_to_nil(params) do
    Map.reject(params, fn {_k, v} -> v == "" end)
  end

  defp put_expires_at(params) do
    case Integer.parse(to_string(params["expires_in_days"])) do
      {days, _} when days > 0 ->
        Map.put(params, "expires_at", DateTime.add(Clock.now_utc(), days * 86_400, :second))

      _ ->
        params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      org={@org}
      current_path={assigns[:admin_path]}
      back="Cupons"
      back_to={~p"/admin/#{@org.slug}/cupons"}
    >
      <section class="stack-5">
        <.admin_header
          title={if @live_action == :new, do: "Novo cupom público", else: "Editar cupom"}
          eyebrow="Cupom"
        />
        <p class="text-xs text-dim">
          Cupom que qualquer cliente pode usar. Ao criar (ativo), os inscritos recebem um aviso.
        </p>

        <.form for={@form} phx-change="validate" phx-submit="save" class="stack-5" id="coupon-form">
          <.form_section title="Desconto">
            <.input
              field={@form[:code]}
              label="Código (vazio = gerar automático)"
              autocomplete="off"
              placeholder="Ex: BLACKFRIDAY10"
            />
            <div class="field-row">
              <.input
                field={@form[:discount_kind]}
                type="select"
                label="Tipo de desconto"
                options={[{"Porcentagem (%)", "percent"}, {"Valor fixo (centavos)", "fixed"}]}
              />
              <.input
                field={@form[:discount_value]}
                type="number"
                label="Valor do desconto (% ou centavos)"
                required
                inputmode="numeric"
              />
            </div>
          </.form_section>

          <.form_section title="Limites" hint="Tudo opcional: vazio significa sem limite.">
            <.input
              name="coupon[expires_in_days]"
              value={@expires_in_days}
              type="number"
              label="Validade (dias, vazio = sem expirar)"
              inputmode="numeric"
            />
            <div class="field-row">
              <.input
                field={@form[:min_order_cents]}
                type="number"
                label="Pedido mínimo (centavos)"
                inputmode="numeric"
              />
              <.input
                field={@form[:max_uses]}
                type="number"
                label="Limite de usos"
                inputmode="numeric"
              />
            </div>
            <.input field={@form[:is_active]} type="checkbox" label="Ativo" />
          </.form_section>

          <.form_bar>
            <.button type="submit" class="btn--block">
              {if @live_action == :new, do: "Criar cupom", else: "Salvar"}
            </.button>
          </.form_bar>
        </.form>

        <.button
          :if={@live_action == :edit}
          phx-click="delete"
          data-confirm="Apagar este cupom?"
          variant={:danger}
          class="btn--block"
        >
          Apagar cupom
        </.button>
      </section>
    </Layouts.admin>
    """
  end
end
