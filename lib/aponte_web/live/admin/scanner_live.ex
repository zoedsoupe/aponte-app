defmodule AponteWeb.Admin.ScannerLive do
  @moduledoc """
  Validação na porta. LiveView + hook de câmera (`assets/js/scanner.js`):
  o cliente lê o QR e dá `pushEvent("scan", %{code})`; o servidor valida
  atomicamente via `Tickets.validate_ticket/2` (escopado à edição da porta) e
  devolve painel verde/vermelho.

  Cada validação faz broadcast em `"door:<edition_id>"`, então vários celulares
  na porta veem o contador `validadas / vendidas` em tempo real.
  """
  use AponteWeb, :live_view

  alias Aponte.{Clock, Editions, Tickets}

  @impl true
  def mount(params, _session, socket) do
    org = socket.assigns.org

    # Porta da edição selecionada no painel quando vier `:edition_id`; senão a
    # publicada atual (link global do topo). A edição precisa pertencer à org
    # da URL — get_edition_in_org é a guarda contra URL-tampering cross-org.
    case load_edition(org, params) do
      {:ok, edition} ->
        if connected?(socket) and edition do
          Phoenix.PubSub.subscribe(Aponte.PubSub, "door:#{edition.id}")
        end

        {:ok,
         socket
         |> assign(
           scanner: true,
           edition: edition,
           result: nil,
           name_query: "",
           name_matches: [],
           page_title: "Porta"
         )
         |> load_stats()}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Edição não encontrada.")
         |> redirect(to: ~p"/admin/#{org.slug}")}
    end
  end

  defp load_edition(org, %{"edition_id" => id}) do
    case Editions.get_edition_in_org(org.id, id) do
      {:ok, edition} -> {:ok, edition}
      {:error, :not_found} -> :error
    end
  end

  defp load_edition(org, _params), do: {:ok, Editions.current_edition(org.id)}

  @impl true
  def handle_event("scan", %{"code" => code}, socket), do: {:noreply, validate(socket, code)}

  def handle_event("manual", %{"code" => code}, socket), do: {:noreply, validate(socket, code)}

  # Busca por nome (S1): comprador sem QR em mãos entra pelo nome — lista os
  # confirmados não validados da edição e cada linha valida com um toque.
  def handle_event("search_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, name_query: name, name_matches: door_matches(socket, name))}
  end

  def handle_event("validate_name", %{"code" => code}, socket) do
    {:noreply,
     socket
     |> validate(code)
     |> assign(name_matches: door_matches(socket, socket.assigns.name_query))}
  end

  def handle_event("clear", _params, socket), do: {:noreply, assign(socket, result: nil)}

  def handle_event("camera_error", %{"name" => name}, socket) do
    msg =
      case name do
        "NotAllowedError" -> "Câmera negada. Use o código manual abaixo."
        "NotFoundError" -> "Nenhuma câmera encontrada. Use o código manual."
        _ -> "Não foi possível abrir a câmera. Use o código manual."
      end

    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:validated, _edition_id}, socket), do: {:noreply, load_stats(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── core ────────────────────────────────────────────────────────────────────

  defp validate(%{assigns: %{edition: nil}} = socket, _code), do: socket

  defp validate(socket, code) do
    result =
      case Tickets.validate_ticket(code, socket.assigns.edition.id) do
        {:ok, ticket} ->
          %{kind: :ok, lote: lote_name(ticket), name: buyer_name(ticket), at: ticket.used_at}

        {:error, {:already_used, ticket}} ->
          %{
            kind: :already_used,
            lote: lote_name(ticket),
            name: buyer_name(ticket),
            at: ticket.used_at
          }

        {:error, :not_found} ->
          %{kind: :not_found}
      end

    socket |> assign(result: result) |> load_stats()
  end

  defp lote_name(ticket) do
    case Editions.get_ticket_type!(ticket.ticket_type_id) do
      %{name: name} -> name
    end
  rescue
    Ecto.NoResultsError -> "Ingresso"
  end

  defp buyer_name(%{order: %{customer_name: name}}), do: name
  defp buyer_name(_), do: ""

  defp load_stats(%{assigns: %{edition: nil}} = socket), do: assign(socket, stats: nil)

  defp load_stats(%{assigns: %{edition: edition}} = socket),
    do: assign(socket, stats: Tickets.stats(edition.id))

  defp door_matches(%{assigns: %{edition: nil}}, _name), do: []

  defp door_matches(%{assigns: %{edition: edition, org: org}}, name),
    do: Tickets.search_door_tickets(org.id, edition.id, name)

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section id="scanner" phx-hook="Scanner" data-scanner class="scanner stack-4">
        <p :if={is_nil(@edition)} class="text-sm text-dim">
          Nenhuma edição publicada. Publique uma edição pra abrir a porta.
        </p>

        <%= if @edition do %>
          <header class="stack-1">
            <p class="eyebrow">Porta</p>
            <h1 class="text-xl">{@edition.name}</h1>
          </header>

          <%!-- contador ao vivo: glanceable, mono, broadcast door:<edition> --%>
          <p :if={@stats} class="door-count">
            validadas {@stats.validated} / vendidas {@stats.sold_confirmed}
          </p>

          <div id="cam-wrap" phx-update="ignore" class="scanner-cam">
            <video data-scanner-video playsinline autoplay muted class="scanner-video"></video>
          </div>

          <button type="button" data-scanner-activate class="btn btn--primary btn--block">
            Ativar câmera
          </button>

          <form phx-submit="manual" id="manual-code-form" class="stack-2">
            <label class="field stack-1">
              <span class="field-label text-xs text-muted">Código manual</span>
              <input
                type="text"
                name="code"
                autocomplete="off"
                autocapitalize="characters"
                placeholder="XXXX-XXXX"
                class="input text-mono"
              />
            </label>
            <.button type="submit" variant={:ghost} class="btn--block">Validar código</.button>
          </form>

          <%!-- busca por nome: comprador sem QR entra pelo nome, um toque valida --%>
          <form
            phx-change="search_name"
            phx-submit="search_name"
            id="name-search-form"
            class="stack-2"
          >
            <label class="field stack-1">
              <span class="field-label text-xs text-muted">Buscar por nome</span>
              <input
                type="text"
                name="name"
                value={@name_query}
                phx-debounce="300"
                autocomplete="off"
                placeholder="nome de quem comprou"
                class="input"
              />
            </label>
          </form>

          <ul :if={@name_matches != []} class="door-matches">
            <li :for={t <- @name_matches} class="door-match">
              <span class="door-match-name">
                {t.order.customer_name}
                <span class="text-mono text-xs text-dim">
                  {Aponte.Tickets.Ticket.display_code(t)}
                </span>
              </span>
              <.button phx-click="validate_name" phx-value-code={t.code}>Validar</.button>
            </li>
          </ul>
          <p
            :if={@name_matches == [] and String.length(String.trim(@name_query)) >= 2}
            class="text-sm text-dim"
          >
            Nenhum ingresso confirmado com esse nome.
          </p>
        <% end %>

        <%!-- painel de resultado fullscreen --%>
        <div
          :if={@result}
          class={["scan-result", scan_result_class(@result.kind)]}
          phx-click="clear"
          role="status"
        >
          <div class="scan-result-inner stack-2">
            <%= case @result.kind do %>
              <% :ok -> %>
                <span class="scan-result-mark">✓</span>
                <span class="text-xl text-mono">{@result.lote}</span>
                <span :if={@result.name != ""} class="text-base">{@result.name}</span>
                <span class="text-sm text-dim">Entrou {Clock.format(@result.at, :time)}</span>
              <% :already_used -> %>
                <span class="scan-result-mark">✕</span>
                <span class="text-xl text-mono">Já validado</span>
                <span :if={@result.lote} class="text-base">{@result.lote}</span>
                <span :if={@result.name not in [nil, ""]} class="text-base">{@result.name}</span>
                <span class="text-sm">Entrou às {Clock.format(@result.at, :time)}</span>
              <% :not_found -> %>
                <span class="scan-result-mark">✕</span>
                <span class="text-xl text-mono">Não encontrado</span>
            <% end %>
            <span class="text-xs text-dim">Toque pra continuar</span>
          </div>
        </div>
      </section>
    </Layouts.admin>
    """
  end

  defp scan_result_class(:ok), do: "scan-result--ok"
  defp scan_result_class(_), do: "scan-result--err"
end
