defmodule AponteWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limit por IP via ETS (sem deps). Janela deslizante simples por bucket.

  Uso: `plug AponteWeb.Plugs.RateLimit, max: 5, window_ms: 3_600_000, bucket: "tocar"`

  Excedido → 429 e `halt`. App single-node (SQLite), então ETS local basta.
  """

  import Plug.Conn
  import Phoenix.Component

  alias AponteWeb.Layouts

  @table :sesh_rate_limit

  def init(opts) do
    %{
      max: Keyword.get(opts, :max, 5),
      window_ms: Keyword.get(opts, :window_ms, 3_600_000),
      bucket: Keyword.get(opts, :bucket, "default")
    }
  end

  def call(conn, %{max: max, window_ms: window_ms, bucket: bucket}) do
    ensure_table()
    key = {bucket, client_ip(conn)}
    now = System.monotonic_time(:millisecond)

    hits =
      :ets.lookup(@table, key)
      |> case do
        [{^key, timestamps}] -> Enum.filter(timestamps, &(&1 > now - window_ms))
        [] -> []
      end

    if length(hits) >= max do
      too_many_requests(conn)
    else
      :ets.insert(@table, {key, [now | hits]})
      conn
    end
  end

  # 429 dentro do shell da org quando a org já foi carregada (os pipelines que
  # usam o limiter rodam depois de LoadOrg); página mínima estilizada se não -
  # o limiter nunca pode derrubar a requisição por erro de render.
  defp too_many_requests(conn) do
    org = conn.assigns[:org]

    html =
      %{org: org, dm_url: org && AponteWeb.Instagram.dm_url(org.instagram)}
      |> rate_limit_page()
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(429, html)
    |> halt()
  end

  defp rate_limit_page(%{org: nil} = assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pt-br" style="--accent:#BF7262">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Calma aí - Aponte</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <link rel="stylesheet" href="/assets/css/app.css" />
      </head>
      <body class="bg-base text-fg text-sans">
        <main class="shell error-page stack-4">
          <p class="text-2xl">Calma aí</p>
          <p class="text-base text-muted">
            Muitas tentativas seguidas. Espera alguns minutos e tenta de novo.
          </p>
        </main>
      </body>
    </html>
    """
  end

  defp rate_limit_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pt-br" style={"--accent:#{@org.accent_color}"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{"Calma aí - #{@org.name}"}</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <link rel="stylesheet" href="/assets/css/app.css" />
      </head>
      <body class="bg-base text-fg text-sans">
        <Layouts.app flash={%{}} org={@org} current_path={nil}>
          <section class="stack-4">
            <h1 class="text-xl">Calma aí</h1>
            <p class="text-base">
              Muitas tentativas seguidas. Espera alguns minutos e tenta de novo.
            </p>
            <p class="text-sm text-dim">
              Se for urgente, chama a {@org.name} no Instagram.
            </p>
            <a :if={@dm_url} href={@dm_url} class="btn btn--primary btn--block">
              Falar com a {@org.name} no Instagram
            </a>
          </section>
        </Layouts.app>
      </body>
    </html>
    """
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp client_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
