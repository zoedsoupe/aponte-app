defmodule AponteWeb.DjController do
  use AponteWeb, :controller

  alias Aponte.DjApplications

  # Tempo mínimo (s) entre carregar o form e enviar. Humano não preenche
  # 5 campos em < 3s; bot que faz POST direto não espera.
  @min_fill_seconds 3
  @ts_salt "dj_form"

  def new(conn, _params) do
    # The DJ form is bespoke to SESH and lives as a section of the org's sobre
    # page (custom-pages model). SESH gets redirected to it; other orgs 404.
    if conn.assigns.org.slug == "sesh" do
      redirect(conn, to: ~p"/#{conn.assigns.org.slug}/sobre" <> "#tocar")
    else
      conn
      |> put_status(:not_found)
      |> put_root_layout(false)
      |> put_view(AponteWeb.ErrorHTML)
      |> render("404.html")
      |> halt()
    end
  end

  @doc """
  Signed form-load timestamp consumed by `create/2` (anti-bot pacing). The
  sobre page renders the form, so it signs through here to share the salt.
  """
  def sign_form_ts(conn), do: sign_ts(conn)

  def create(conn, params) do
    cond do
      # ponytail: silent_ok com inscrições fechadas significa que um humano que
      # tinha o form aberto quando fechou recebe um sucesso falso — aceitável
      # (revisão manual, nada persiste); troca por flash + re-render se importar.
      not Aponte.Settings.dj_applications_open?() -> silent_ok(conn)
      # Honeypot: campo "site" escondido; bot preenche, humano não.
      honeypot_filled?(params) -> silent_ok(conn)
      # Timestamp assinado: rejeita POST instantâneo (bot) sem dar pista.
      not human_paced?(conn, params["ts"]) -> silent_ok(conn)
      true -> persist(conn, Map.get(params, "dj_application", %{}))
    end
  end

  defp persist(conn, attrs) do
    org = conn.assigns.org

    case DjApplications.create(org, attrs) do
      {:ok, _application} ->
        redirect(conn, to: ~p"/#{org.slug}/sobre?ok=1" <> "#tocar")

      {:error, %Ecto.Changeset{} = cs} ->
        # The form lives in the sobre page now — re-render it there with the
        # errored changeset so the user keeps their input.
        conn
        |> put_flash(:error, "Confere os campos e tenta de novo.")
        |> put_view(AponteWeb.OrgHTML)
        |> render(:about,
          org: org,
          page_title: "Sobre - #{org.name}",
          dj_changeset: %{cs | action: :insert},
          dj_submitted: false,
          dj_form_ts: sign_ts(conn),
          dj_open?: Aponte.Settings.dj_applications_open?()
        )
    end
  end

  # Sucesso silencioso: bot acha que passou, nada persiste.
  defp silent_ok(conn) do
    redirect(conn, to: ~p"/#{conn.assigns.org.slug}/sobre?ok=1" <> "#tocar")
  end

  defp honeypot_filled?(params) do
    case params["site"] do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  defp sign_ts(conn), do: Phoenix.Token.sign(conn, @ts_salt, System.system_time(:second))

  defp human_paced?(conn, ts) when is_binary(ts) do
    case Phoenix.Token.verify(conn, @ts_salt, ts, max_age: 3600) do
      {:ok, signed_at} -> System.system_time(:second) - signed_at >= @min_fill_seconds
      _ -> false
    end
  end

  defp human_paced?(_conn, _ts), do: false
end
