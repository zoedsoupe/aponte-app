defmodule AponteWeb.Admin.OrgGalleryLive do
  @moduledoc """
  Org gallery (/admin/:org_slug/galeria): upload, list, delete and reorder the
  vitrine photos.

  Upload flow (spec section 7), in-request inside `consume_uploaded_entries`:
  content hash -> soft quota check (flash warning when over, still inserts) ->
  configured `Images.Processor` -> `Orgs.add_image/2` (same file twice =
  `{:error, :duplicate}`, flash "imagem ja enviada"). Reorder is up/down
  buttons emitting the full id list to `Orgs.reorder_images/2` (no drag).
  """
  use AponteWeb, :live_view

  alias Aponte.{Images, Orgs, Uploads}

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.org

    {:ok,
     socket
     |> assign(images: Orgs.list_images(org.id), page_title: "Galeria")
     |> allow_upload(:images,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 10,
       max_file_size: 5_000_000
     )}
  end

  # ── events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    org = socket.assigns.org
    Uploads.ensure_dirs!(org.id)

    results =
      consume_uploaded_entries(socket, :images, fn %{path: tmp}, entry ->
        {:ok, store_image(org, tmp, entry)}
      end)

    {:noreply,
     socket
     |> flash_results(results)
     |> assign(images: Orgs.list_images(org.id))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    org = socket.assigns.org

    case Enum.find(socket.assigns.images, &(&1.id == id)) do
      nil ->
        :ok

      image ->
        Uploads.delete_quiet(Path.join(Uploads.org_dir(org.id), image.path))
        Uploads.delete_quiet(Path.join(Uploads.org_dir(org.id), image.thumb_path))
        {:ok, _} = Orgs.delete_image(image)
    end

    {:noreply, assign(socket, images: Orgs.list_images(org.id))}
  end

  def handle_event("move", %{"id" => id, "dir" => dir}, socket) do
    org = socket.assigns.org
    images = socket.assigns.images
    index = Enum.find_index(images, &(&1.id == id))
    target = if dir == "up", do: index - 1, else: index + 1

    if index && target >= 0 && target < length(images) do
      ids =
        images
        |> Enum.map(& &1.id)
        |> List.replace_at(index, Enum.at(images, target).id)
        |> List.replace_at(target, id)

      :ok = Orgs.reorder_images(org.id, ids)
    end

    {:noreply, assign(socket, images: Orgs.list_images(org.id))}
  end

  # ── upload core ─────────────────────────────────────────────────────────────

  defp store_image(org, tmp_path, entry) do
    hash = Uploads.content_hash(tmp_path)
    quota = Orgs.check_upload_quota(org, entry.client_size, enforce?: false)

    case Images.process(tmp_path, Uploads.org_dir(org.id), hash) do
      {:ok, %{web: web, thumb: thumb, byte_size: byte_size}} ->
        attrs = %{
          path: Path.basename(web),
          thumb_path: Path.basename(thumb),
          content_hash: hash,
          byte_size: byte_size,
          original_filename: entry.client_name
        }

        case Orgs.add_image(org, attrs) do
          {:ok, _image} -> if(quota == {:ok, :over_quota}, do: :over, else: :ok)
          {:error, :duplicate} -> :duplicate
          {:error, _changeset} -> :error
        end

      {:error, _} ->
        :error
    end
  end

  defp flash_results(socket, []) do
    put_flash(socket, :error, "Nenhuma imagem pra enviar.")
  end

  defp flash_results(socket, results) do
    oks = Enum.count(results, &(&1 in [:ok, :over]))
    dups = Enum.count(results, &(&1 == :duplicate))
    errs = Enum.count(results, &(&1 == :error))
    over? = :over in results

    socket
    |> maybe_flash(oks > 0, :info, "#{oks} imagem(ns) adicionada(s).")
    |> maybe_flash(over?, :info, "Atenção: a org passou da quota de armazenamento.")
    |> maybe_flash(dups > 0, :error, "imagem ja enviada")
    |> maybe_flash(errs > 0, :error, "#{errs} imagem(ns) falharam (arquivo inválido?).")
  end

  defp maybe_flash(socket, true, kind, msg), do: put_flash(socket, kind, msg)
  defp maybe_flash(socket, false, _kind, _msg), do: socket

  defp image_url(org, filename), do: "/uploads/orgs/#{org.id}/#{filename}"

  defp upload_error_message(:too_large), do: "Arquivo grande demais (máx 5 MB)"
  defp upload_error_message(:not_accepted), do: "Formato não aceito (use jpg, png ou webp)"
  defp upload_error_message(:too_many_files), do: "Máximo de 10 por vez"
  defp upload_error_message(other), do: to_string(other)

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} back="Painel">
      <section class="stack-5">
        <header class="stack-1">
          <h1 class="text-xl text-mono">Galeria</h1>
          <p class="text-xs text-dim">
            Fotos da vitrine pública da org. Até 10 por vez, 5 MB cada.
          </p>
        </header>

        <form phx-submit="save" phx-change="validate" id="gallery-form" class="stack-2">
          <label class="dropzone" phx-drop-target={@uploads.images.ref}>
            <.live_file_input upload={@uploads.images} class="dropzone-input" />
            <span class="text-xs text-muted">enviar fotos (jpg/png/webp, até 5 MB)</span>
          </label>

          <div :for={entry <- @uploads.images.entries} class="upload-entry">
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
            <p :for={err <- upload_errors(@uploads.images, entry)} class="field-error">
              {upload_error_message(err)}
            </p>
          </div>

          <p :for={err <- upload_errors(@uploads.images)} class="field-error">
            {upload_error_message(err)}
          </p>

          <.button
            type="submit"
            class="btn--block"
            disabled={@uploads.images.entries == []}
            id="gallery-submit"
          >
            Enviar
          </.button>
        </form>

        <p :if={@images == []} class="text-sm text-dim">Nenhuma foto ainda.</p>

        <ul class="stack-2" id="gallery-list">
          <li :for={{img, i} <- Enum.with_index(@images)} class="card row gap-3 align-center">
            <img src={image_url(@org, img.thumb_path)} alt="" width="64" height="64" />
            <span class="text-xs text-mono flex-1">{img.original_filename || img.path}</span>
            <span class="row gap-2">
              <button
                type="button"
                phx-click="move"
                phx-value-id={img.id}
                phx-value-dir="up"
                disabled={i == 0}
                class="btn btn--ghost btn--sm"
              >
                subir
              </button>
              <button
                type="button"
                phx-click="move"
                phx-value-id={img.id}
                phx-value-dir="down"
                disabled={i == length(@images) - 1}
                class="btn btn--ghost btn--sm"
              >
                descer
              </button>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={img.id}
                data-confirm="Excluir esta foto?"
                class="btn btn--ghost btn--sm"
              >
                Excluir
              </button>
            </span>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
