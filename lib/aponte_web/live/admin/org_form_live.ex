defmodule AponteWeb.Admin.OrgFormLive do
  @moduledoc """
  Org create (/admin/organizacoes/nova) and edit (/admin/:org_slug/perfil).

  The slug is set on create only (immutable afterwards: the input renders
  disabled and any submitted slug param is dropped on :edit). The logo reuses
  the gallery pipeline: content hash, stored under `Uploads.org_dir/1`, svg
  copied raw (no vips), raster through the configured `Images.Processor`.
  """
  use AponteWeb, :live_view

  alias Aponte.{Images, Orgs, Uploads}
  alias Aponte.Orgs.Org

  @max_logo 5_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_record(socket.assigns.live_action)
     |> allow_upload(:logo,
       accept: ~w(.jpg .jpeg .png .webp .svg),
       max_entries: 1,
       max_file_size: @max_logo
     )}
  end

  # ── events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"org" => params}, socket) do
    changeset =
      socket.assigns.record
      |> Orgs.change_org(attrs_from(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), social_links: social_rows(params))}
  end

  def handle_event("save", %{"org" => params}, %{assigns: %{live_action: :new}} = socket) do
    case Orgs.create_org(attrs_from(params)) do
      {:ok, org} ->
        case consume_logo(org, socket) do
          {:ok, org} ->
            {:noreply,
             socket
             |> put_flash(:info, "Organização criada.")
             |> push_navigate(to: ~p"/admin/#{org.slug}")}

          {:error, :logo} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Org criada, mas a logo não é uma imagem válida. Envie de novo no perfil."
             )
             |> push_navigate(to: ~p"/admin/#{org.slug}/perfil")}
        end

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Confira os campos abaixo.")
         |> assign(form: to_form(changeset), social_links: social_rows(params))}
    end
  end

  def handle_event("save", %{"org" => params}, socket) do
    # Slug is immutable after create.
    attrs = params |> Map.delete("slug") |> attrs_from()

    case Orgs.update_org(socket.assigns.org, attrs) do
      {:ok, org} ->
        case consume_logo(org, socket) do
          {:ok, org} ->
            {:noreply, socket |> put_flash(:info, "Perfil salvo.") |> assign_form(org)}

          {:error, :logo} ->
            {:noreply,
             socket
             |> put_flash(:error, "Perfil salvo, mas a logo não é uma imagem válida.")
             |> assign_form(org)}
        end

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Confira os campos abaixo.")
         |> assign(form: to_form(changeset), social_links: social_rows(params))}
    end
  end

  def handle_event("add_social_link", _params, socket) do
    row = %{"label" => "", "url" => ""}
    {:noreply, assign(socket, social_links: socket.assigns.social_links ++ [row])}
  end

  def handle_event("remove_social_link", %{"index" => index}, socket) do
    links = List.delete_at(socket.assigns.social_links, index_of(index))
    {:noreply, assign(socket, social_links: links)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  # ── data ────────────────────────────────────────────────────────────────────

  defp assign_record(socket, :new) do
    assign_form(socket, %Org{accent_color: "#BF7262"})
  end

  defp assign_record(socket, :edit) do
    assign_form(socket, socket.assigns.org)
  end

  defp assign_form(socket, %Org{} = org) do
    socket
    |> assign(
      record: org,
      social_links: org.social_links,
      page_title: if(org.id, do: "Perfil — #{org.name}", else: "Nova organização"),
      form: to_form(Orgs.change_org(org))
    )
    |> then(fn socket ->
      if org.id, do: assign(socket, org: org), else: socket
    end)
  end

  # Form params -> changeset attrs: social_links arrive as an indexed map
  # ("org[social_links][0][label]") and become a plain list, fully-empty rows
  # dropped (the changeset only validates rows the admin actually filled).
  defp attrs_from(params) do
    Map.put(params, "social_links", params |> social_rows() |> drop_empty_rows())
  end

  # Rows for rendering: trimmed but NOT dropped, so an in-progress empty row
  # survives phx-change re-renders.
  defp social_rows(params) do
    case params["social_links"] do
      nil ->
        []

      links when is_map(links) ->
        links
        |> Enum.sort_by(fn {index, _} -> index_of(index) end)
        |> Enum.map(fn {_, row} ->
          %{
            "label" => String.trim(row["label"] || ""),
            "url" => String.trim(row["url"] || "")
          }
        end)

      links when is_list(links) ->
        links
    end
  end

  defp drop_empty_rows(rows) do
    Enum.reject(rows, fn %{"label" => label, "url" => url} -> label == "" and url == "" end)
  end

  defp index_of(key) do
    case Integer.parse(to_string(key)) do
      {n, _} -> n
      :error -> 0
    end
  end

  # ── logo ────────────────────────────────────────────────────────────────────

  defp consume_logo(org, socket) do
    case consume_uploaded_entries(socket, :logo, fn %{path: tmp}, entry ->
           {:ok, store_logo(org, tmp, entry)}
         end) do
      [] -> {:ok, org}
      [{:ok, filename}] -> Orgs.update_org(org, %{logo_path: filename})
      [:error] -> {:error, :logo}
    end
  end

  # Content-hashed filename under the org's uploads dir. svg bypasses vips and
  # is copied raw (the vitrine serves it as-is); raster goes through the
  # configured processor and keeps the web variant as the logo.
  defp store_logo(org, tmp_path, entry) do
    Uploads.ensure_dirs!(org.id)
    hash = Uploads.content_hash(tmp_path)

    if svg?(entry) do
      filename = hash <> ".svg"
      File.cp!(tmp_path, Path.join(Uploads.org_dir(org.id), filename))
      {:ok, filename}
    else
      case Images.process(tmp_path, Uploads.org_dir(org.id), hash) do
        {:ok, %{web: web}} -> {:ok, Path.basename(web)}
        {:error, _} -> :error
      end
    end
  end

  defp svg?(entry) do
    entry.client_type == "image/svg+xml" or
      entry.client_name |> Path.extname() |> String.downcase() == ".svg"
  end

  # Only called under `:if={@record.logo_path}` in the template.
  defp logo_url(org), do: "/uploads/orgs/#{org.id}/#{org.logo_path}"

  defp upload_error_message(:too_large), do: "Arquivo grande demais (máx 5 MB)"
  defp upload_error_message(:not_accepted), do: "Formato não aceito (use jpg, png, webp ou svg)"
  defp upload_error_message(:too_many_files), do: "Só um arquivo"
  defp upload_error_message(other), do: to_string(other)

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={assigns[:org]} back={@live_action == :edit && "Painel"}>
      <section class="stack-5">
        <h1 class="text-xl text-mono">
          {if @live_action == :new, do: "Nova organização", else: "Perfil — #{@record.name}"}
        </h1>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          id="org-form"
          class="stack-3"
          multipart
        >
          <.input field={@form[:name]} label="Nome" required />

          <%!-- slug is immutable: only asked on create, never rendered on edit --%>
          <.input
            :if={@live_action == :new}
            field={@form[:slug]}
            label="Slug (minúsculas, números ou hífen; não dá pra mudar depois)"
            required
            autocomplete="off"
          />

          <.input
            field={@form[:about]}
            type="textarea"
            label="Sobre (uma linha em branco separa parágrafos)"
            rows="5"
          />

          <.color_input field={@form[:accent_color]} label="Cor de destaque" fallback="#BF7262" />
          <.color_input field={@form[:bg_color]} label="Cor de fundo" fallback="#FEF8DA" />
          <.color_input field={@form[:fg_color]} label="Cor do texto" fallback="#49422F" />
          <p class="text-xs text-dim">
            Fundo e texto sem customização herdam a paleta padrão da Aponte.
          </p>

          <.input field={@form[:instagram]} label="Instagram (sem @)" autocomplete="off" />
          <.input field={@form[:pix_key]} label="Chave PIX (recebe as vendas)" autocomplete="off" />

          <%!-- links sociais: linhas label + url, adiciona/remove dinamicamente --%>
          <fieldset class="stack-2">
            <legend class="text-sm text-muted">Links sociais</legend>

            <div :for={{link, i} <- Enum.with_index(@social_links)} class="row gap-2 align-center">
              <input
                type="text"
                name={"#{@form[:social_links].name}[#{i}][label]"}
                value={link["label"]}
                placeholder="label"
                class="field-input flex-1"
              />
              <input
                type="text"
                name={"#{@form[:social_links].name}[#{i}][url]"}
                value={link["url"]}
                placeholder="https://"
                class="field-input flex-1"
              />
              <button
                type="button"
                phx-click="remove_social_link"
                phx-value-index={i}
                class="btn btn--ghost btn--sm"
                aria-label="remover link"
              >
                Remover
              </button>
            </div>

            <p :for={{msg, _} <- @form[:social_links].errors} class="field-error">{msg}</p>

            <button type="button" phx-click="add_social_link" class="btn btn--ghost btn--block">
              + Adicionar link
            </button>
          </fieldset>

          <%!-- logo: mesmo pipeline da galeria (hash + orgs/:org_id/) --%>
          <div class="field stack-2">
            <span class="field-label">Logo (opcional)</span>

            <div :if={@record.logo_path} class="photo-preview">
              <img src={logo_url(@record)} alt="logo atual" width="120" />
            </div>

            <label class="dropzone" phx-drop-target={@uploads.logo.ref}>
              <.live_file_input upload={@uploads.logo} class="dropzone-input" />
              <span class="text-xs text-muted">
                {if @record.logo_path, do: "trocar", else: "enviar"} (jpg/png/webp/svg, até 5 MB)
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

          <.button type="submit" class="btn--block">
            {if @live_action == :new, do: "Criar organização", else: "Salvar"}
          </.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :fallback, :string, required: true

  defp color_input(assigns) do
    assigns = assign(assigns, :value, assigns.field.value || assigns.fallback)

    ~H"""
    <div class="field stack-1">
      <span class="field-label">{@label}</span>
      <div class="row gap-3 align-center">
        <input type="color" name={@field.name} id={@field.id} value={@value} class="color-input" />
        <span class="text-mono text-xs">{@value}</span>
        <span
          class="swatch"
          style={"background-color:#{@value};width:1.5rem;height:1.5rem;border-radius:4px;display:inline-block"}
        >
        </span>
      </div>
    </div>
    """
  end
end
