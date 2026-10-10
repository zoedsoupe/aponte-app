defmodule AponteWeb.Admin.EditionFormLive do
  use AponteWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Aponte.{Clock, Editions, Merch, Notifications}
  alias Aponte.Editions.Edition

  @max_logo 2_000_000

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_edition(params, socket.assigns.live_action)
     |> allow_upload(:logo, accept: ~w(.svg .png), max_entries: 1, max_file_size: @max_logo)}
  end

  # ── events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"edition" => params}, socket) do
    changeset =
      socket.assigns.edition
      |> Editions.change_edition(munge_params(params))
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket,
       form: to_form(changeset),
       starts_at_local: params["starts_at"],
       price_inputs: price_inputs(params)
     )}
  end

  def handle_event("save", %{"edition" => params}, %{assigns: %{live_action: :new}} = socket) do
    org = socket.assigns.org
    params = params |> munge_params() |> put_logo(socket, params["number"])

    case Editions.create_edition(org, params) do
      {:ok, edition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Edição \"#{edition.name}\" criada. Publique quando estiver pronta.")
         |> push_navigate(to: ~p"/admin/#{org.slug}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Confira os campos abaixo.")
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("save", %{"edition" => params}, socket) do
    edition = socket.assigns.edition
    params = params |> munge_params() |> put_logo(socket, to_string(edition.number))

    case Editions.update_edition(edition, params) do
      {:ok, _edition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Edição salva.")
         |> push_navigate(to: ~p"/admin/#{socket.assigns.org.slug}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, error_flash(changeset))
         |> assign(form: to_form(changeset))}
    end
  end

  def handle_event("publish", _params, socket) do
    case Editions.publish(socket.assigns.edition) do
      {:ok, edition} ->
        Notifications.announce_edition(edition)

        {:noreply,
         socket
         |> put_flash(:info, "Edição publicada (qualquer outra publicada foi arquivada).")
         |> assign_form(Editions.get_edition!(edition.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível publicar.")}
    end
  end

  def handle_event("archive", _params, socket) do
    {:ok, edition} = Editions.archive(socket.assigns.edition)
    {:noreply, socket |> put_flash(:info, "Edição arquivada.") |> assign_form(edition)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  def handle_event("remove-logo", _params, socket) do
    {:ok, edition} = Editions.update_edition(socket.assigns.edition, %{logo_path: nil})
    {:noreply, socket |> put_flash(:info, "Logo removida.") |> assign_form(edition)}
  end

  def handle_event("save_featured", %{"featured" => ids}, socket) do
    ids = List.wrap(ids)
    Editions.set_featured_merch(socket.assigns.edition.id, ids)

    {:noreply,
     socket |> put_flash(:info, "Produtos em destaque salvos.") |> assign(featured_ids: ids)}
  end

  def handle_event("save_featured", _params, socket) do
    Editions.set_featured_merch(socket.assigns.edition.id, [])
    {:noreply, socket |> put_flash(:info, "Destaques limpos.") |> assign(featured_ids: [])}
  end

  # ── data ────────────────────────────────────────────────────────────────────

  defp assign_edition(socket, _params, :new), do: assign_form(socket, %Edition{ticket_types: []})

  defp assign_edition(socket, %{"id" => id}, :edit) do
    # Guarda contra URL-tampering cross-org: a edição precisa ser da org da URL.
    case Editions.get_edition_in_org(socket.assigns.org.id, id) do
      {:ok, edition} ->
        assign_form(socket, edition)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Edição não encontrada.")
        |> redirect(to: ~p"/admin/#{socket.assigns.org.slug}")
    end
  end

  defp assign_form(socket, %Edition{} = edition) do
    socket
    |> assign(
      edition: edition,
      page_title: edition.name || "Nova edição",
      starts_at_local: starts_at_local(edition.starts_at),
      price_inputs: %{},
      form: to_form(Editions.change_edition(edition))
    )
    |> assign_featured_merch(edition)
  end

  # Featured-merch picker só faz sentido numa edição já criada (precisa de id).
  defp assign_featured_merch(socket, %Edition{id: nil}) do
    assign(socket, all_merch: [], featured_ids: [])
  end

  defp assign_featured_merch(socket, %Edition{id: id}) do
    assign(socket,
      all_merch: Merch.list_active_items(socket.assigns.org.id),
      featured_ids: Editions.featured_merch_ids(id)
    )
  end

  # The datetime-local input is BRT; storage is UTC. Price inputs are reais
  # ("35", "35,00", "35.00"); storage is cents. Convert both on the way in.
  defp munge_params(params), do: params |> to_utc() |> prices_to_cents()

  defp to_utc(%{"starts_at" => v} = params) when is_binary(v) and v != "" do
    case parse_local(v) do
      {:ok, utc} -> Map.put(params, "starts_at", DateTime.to_iso8601(utc))
      :error -> params
    end
  end

  defp to_utc(params), do: params

  # Preço digitado em reais vira centavos dentro de cada lote. Valor inválido
  # passa cru — o changeset marca o erro no campo.
  defp prices_to_cents(%{"ticket_types" => types} = params) when is_map(types) do
    Map.put(params, "ticket_types", Map.new(types, fn {k, v} -> {k, price_to_cents(v)} end))
  end

  defp prices_to_cents(params), do: params

  defp price_to_cents(%{"price_cents" => raw} = type) when is_binary(raw) do
    case parse_price(raw) do
      {:ok, cents} -> Map.put(type, "price_cents", cents)
      :error -> type
    end
  end

  defp price_to_cents(type), do: type

  # Raw digitado por lote (index inteiro, como lot.index), pro input continuar
  # mostrando o que o admin escreveu em vez dos centavos normalizados.
  defp price_inputs(%{"ticket_types" => types}) when is_map(types) do
    Map.new(types, fn {k, v} ->
      case Integer.parse(k) do
        {index, ""} -> {index, Map.get(v, "price_cents")}
        _ -> {k, Map.get(v, "price_cents")}
      end
    end)
  end

  defp price_inputs(_params), do: %{}

  # Aceita "35", "35,00" ou "35.00" e devolve centavos.
  defp parse_price(raw) do
    s = raw |> String.trim() |> String.replace(~r/^R\$\s*/i, "") |> String.trim()

    case Regex.run(~r/^(\d+)(?:[.,](\d{1,2}))?$/, s) do
      [_, reais] ->
        {:ok, String.to_integer(reais) * 100}

      [_, reais, cents] ->
        cents = cents |> String.pad_trailing(2, "0") |> String.to_integer()
        {:ok, String.to_integer(reais) * 100 + cents}

      _ ->
        :error
    end
  end

  defp price_display(inputs, lot) do
    case Map.fetch(inputs, lot.index) do
      {:ok, raw} when is_binary(raw) -> raw
      _ -> format_price(lot[:price_cents].value)
    end
  end

  defp price_preview(inputs, lot) do
    with {:ok, raw} when is_binary(raw) <- Map.fetch(inputs, lot.index),
         {:ok, cents} <- parse_price(raw) do
      money(cents)
    else
      _ -> nil
    end
  end

  defp format_price(cents) when is_integer(cents) do
    reais = div(cents, 100)
    rest = cents |> rem(100) |> abs() |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{reais},#{rest}"
  end

  defp format_price(value), do: to_string(value || "")

  defp parse_local(v) do
    iso = if String.length(v) == 16, do: v <> ":00", else: v

    with {:ok, naive} <- NaiveDateTime.from_iso8601(iso),
         {:ok, dt} <- DateTime.from_naive(naive, Clock.tz()) do
      {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}
    else
      _ -> :error
    end
  end

  defp starts_at_local(nil), do: ""

  defp starts_at_local(%DateTime{} = dt) do
    dt |> Clock.to_brt() |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp put_logo(params, socket, slug_src) do
    slug = slug_from(slug_src)

    case consume_uploaded_entries(socket, :logo, &copy_logo(slug, &1, &2)) do
      [] -> params
      [filename] -> Map.put(params, "logo_path", filename)
    end
  end

  defp copy_logo(slug, %{path: tmp}, %{client_name: name}) do
    Editions.ensure_uploads_dir!()
    ext = name |> Path.extname() |> String.downcase()
    ext = if ext in ~w(.svg .png), do: ext, else: ".png"
    filename = "edition-#{slug}-#{System.system_time(:millisecond)}#{ext}"
    File.cp!(tmp, Path.join(Editions.editions_dir(), filename))
    {:ok, filename}
  end

  defp slug_from(nil), do: "ed"

  defp slug_from(value),
    do: Regex.replace(~r/[^a-z0-9]/i, to_string(value), "") |> String.downcase()

  defp upload_error_message(:too_large), do: "Arquivo grande demais (máx 2 MB)"
  defp upload_error_message(:not_accepted), do: "Formato não aceito (use svg ou png)"
  defp upload_error_message(:too_many_files), do: "Só um arquivo"
  defp upload_error_message(other), do: to_string(other)

  defp accent(form), do: form[:accent_color].value || "#F07BC0"

  defp error_flash(changeset) do
    case changeset.errors[:ticket_types] do
      {msg, _} -> msg
      _ -> "Confira os campos abaixo."
    end
  end

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section class="stack-5">
        <.admin_header
          title={if @live_action == :new, do: "Nova edição", else: @edition.name}
          eyebrow="Edição"
        >
          <:actions>
            <.status_badge :if={@edition.id} status={@edition.status} />
          </:actions>
        </.admin_header>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          id="edition-form"
          class="stack-5"
          multipart
        >
          <.form_section title="Edição">
            <div class="field-row">
              <.input
                field={@form[:number]}
                type="number"
                label="Número"
                required
                inputmode="numeric"
              />
              <.input field={@form[:name]} label={"Nome (vazio = \"#{@org.name} #N\")"} />
            </div>

            <label class="field stack-1">
              <span class="field-label">Data e hora (horário de Brasília)</span>
              <input
                type="datetime-local"
                name="edition[starts_at]"
                value={@starts_at_local}
                class="input"
                required
              />
            </label>
          </.form_section>

          <.form_section title="Local e descrição">
            <.input field={@form[:venue]} label="Local" required />
            <.input field={@form[:venue_address]} label="Endereço" />
            <.input
              field={@form[:lineup]}
              type="textarea"
              label="Descrição (uma linha por item)"
              rows="4"
            />
          </.form_section>

          <.form_section title="Identidade visual">
            <div class="field stack-1">
              <span class="field-label">Cor de destaque</span>
              <div class="row gap-3 align-center">
                <input
                  type="color"
                  name="edition[accent_color]"
                  value={accent(@form)}
                  class="color-input"
                />
                <span class="text-mono text-xs">{accent(@form)}</span>
                <span class="swatch" style={"background-color:#{accent(@form)}"}></span>
              </div>
            </div>

            <%!-- logo override (img, sem currentColor) --%>
            <div class="field stack-2">
              <span class="field-label">Logo da edição (opcional)</span>

              <details :if={@edition.logo_path} class="product-detail">
                <summary class="text-xs text-dim">Ver logo atual</summary>
                <div class="photo-preview mt-3">
                  <img src={Editions.logo_url(@edition.logo_path)} alt="logo" width="120" />
                  <button
                    type="button"
                    phx-click="remove-logo"
                    data-confirm="Remover logo atual?"
                    class="btn btn--ghost btn--sm"
                  >
                    Remover
                  </button>
                </div>
              </details>

              <label class="dropzone" phx-drop-target={@uploads.logo.ref}>
                <.live_file_input upload={@uploads.logo} class="dropzone-input" />
                <span class="text-xs text-muted">
                  {if @edition.logo_path, do: "trocar", else: "enviar"} (svg/png, até 2 MB)
                </span>
              </label>

              <div :for={entry <- @uploads.logo.entries} class="upload-entry">
                <span class="text-xs text-mono flex-1">{entry.client_name}</span>
                <progress class="upload-progress" value={entry.progress} max="100">
                  {entry.progress}%
                </progress>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="btn btn--ghost btn--sm"
                >
                  Cancelar
                </button>
                <p :for={err <- upload_errors(@uploads.logo, entry)} class="field-error">
                  {upload_error_message(err)}
                </p>
              </div>

              <p :for={err <- upload_errors(@uploads.logo)} class="field-error">
                {upload_error_message(err)}
              </p>
            </div>
          </.form_section>

          <%!-- lotes inline (cast_assoc + sort/drop) --%>
          <.form_section
            title="Lotes"
            hint="Cada lote é um tipo de ingresso com preço e capacidade próprios."
          >
            <fieldset class="stack-3">
              <legend class="sr-only">Lotes</legend>

              <.inputs_for :let={lot} field={@form[:ticket_types]}>
                <div class="card stack-2">
                  <input type="hidden" name="edition[ticket_types_sort][]" value={lot.index} />

                  <.input field={lot[:name]} label="Nome (ex: Lote 1)" required />
                  <.input
                    field={lot[:description]}
                    type="textarea"
                    label="Descrição / regras (ex: marque 2 amigos no post)"
                    rows="2"
                  />
                  <div class="field-row">
                    <div class="field-stack stack-1">
                      <.input
                        field={lot[:price_cents]}
                        type="text"
                        label="Preço (R$)"
                        value={price_display(@price_inputs, lot)}
                        required
                        inputmode="decimal"
                      />
                      <p :if={price_preview(@price_inputs, lot)} class="text-xs text-dim">
                        = {price_preview(@price_inputs, lot)}
                      </p>
                    </div>
                    <.input
                      field={lot[:capacity]}
                      type="number"
                      label="Capacidade"
                      required
                      inputmode="numeric"
                    />
                    <.input
                      field={lot[:position]}
                      type="number"
                      label="Ordem"
                      inputmode="numeric"
                    />
                  </div>
                  <.input field={lot[:is_active]} type="checkbox" label="À venda" />

                  <button
                    type="button"
                    name="edition[ticket_types_drop][]"
                    value={lot.index}
                    phx-click={JS.dispatch("change")}
                    class="btn btn--ghost btn--sm"
                  >
                    Remover lote
                  </button>
                </div>
              </.inputs_for>

              <input type="hidden" name="edition[ticket_types_drop][]" />

              <button
                type="button"
                name="edition[ticket_types_sort][]"
                value="new"
                phx-click={JS.dispatch("change")}
                class="btn btn--ghost btn--block"
              >
                + Adicionar lote
              </button>
            </fieldset>
          </.form_section>

          <.form_bar>
            <.button type="submit" class="btn--block">
              {if @live_action == :new, do: "Criar edição", else: "Salvar"}
            </.button>
          </.form_bar>
        </.form>

        <.form_section
          :if={@live_action == :edit and @all_merch != []}
          title="Produtos em destaque no /comprar"
          hint="Só estes aparecem no formulário de ingresso. A loja mostra todos."
        >
          <form phx-submit="save_featured" class="stack-2" id="featured-merch-form">
            <label :for={item <- @all_merch} class="field field--inline">
              <input
                type="checkbox"
                name="featured[]"
                value={item.id}
                checked={item.id in @featured_ids}
                class="checkbox"
              />
              <span class="field-label">{item.name} - {money(item.price_cents)}</span>
            </label>
            <.button type="submit" variant={:ghost} class="btn--block">Salvar destaques</.button>
          </form>
        </.form_section>

        <div :if={@edition.id} class="stack-2">
          <.button
            :if={@edition.status != :published}
            phx-click="publish"
            data-confirm="Publicar esta edição? A landing passa a mostrá-la e qualquer outra publicada é arquivada."
            class="btn--block"
          >
            Publicar
          </.button>

          <.button
            :if={@edition.status == :published}
            phx-click="archive"
            data-confirm="Despublicar? A landing volta pro teaser."
            variant={:danger}
            class="btn--block"
          >
            Despublicar
          </.button>
        </div>
      </section>
    </Layouts.admin>
    """
  end
end
