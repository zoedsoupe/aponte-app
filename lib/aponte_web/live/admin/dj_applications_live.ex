defmodule AponteWeb.Admin.DjApplicationsLive do
  use AponteWeb, :live_view

  alias Aponte.{Clock, DjApplications}
  alias AponteWeb.Instagram

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.org

    {:ok,
     assign(socket,
       applications: DjApplications.list(org.id),
       open?: Aponte.Settings.dj_applications_open?(),
       page_title: "Quer tocar"
     )}
  end

  @impl true
  def handle_event("toggle_open", _params, socket) do
    next = not socket.assigns.open?
    {:ok, _} = Aponte.Settings.set_dj_applications_open(next)
    {:noreply, assign(socket, open?: next)}
  end

  # Brazilian numbers come in as DDD + número (10–11 dígitos); prepend country
  # code for the wa.me deep-link unless it's already there.
  defp wa_url(digits) when is_binary(digits) do
    full = if String.length(digits) <= 11, do: "55" <> digits, else: digits
    "https://wa.me/" <> full
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} org={@org} current_path={assigns[:admin_path]} back="Painel">
      <section class="stack-5">
        <.admin_header title="Quer tocar?" eyebrow={"#{length(@applications)} inscrição(ões)"}>
          <:actions>
            <span class="text-xs text-dim">
              Inscrições {if @open?, do: "abertas", else: "fechadas"}
            </span>
            <button type="button" phx-click="toggle_open" class="btn btn--ghost btn--sm">
              {if @open?, do: "Fechar", else: "Abrir"}
            </button>
          </:actions>
        </.admin_header>

        <p :if={@applications == []} class="text-sm text-dim">Nenhuma inscrição ainda.</p>

        <table :if={@applications != []} class="data-table">
          <thead>
            <tr>
              <th>Nome</th>
              <th>Estilos</th>
              <th>Sobre</th>
              <th>Contato</th>
              <th>Data</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @applications}>
              <td class="td-title">{a.name}</td>
              <td data-label="Estilos">{a.musical_styles}</td>
              <td data-label="Sobre" class="text-dim">
                <span class="clamp-2">{a.about}</span>
              </td>
              <td data-label="Contato">
                <div class="row gap-3">
                  <a href={wa_url(a.whatsapp)} target="_blank" rel="noopener" class="text-accent">
                    Whatsapp
                  </a>
                  <a
                    href={Instagram.profile_url(a.instagram)}
                    target="_blank"
                    rel="noopener"
                    class="text-accent"
                  >
                    @{a.instagram}
                  </a>
                </div>
              </td>
              <td data-label="Data" class="text-mono text-dim">
                {Clock.format(a.inserted_at, :date)}
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.admin>
    """
  end
end
