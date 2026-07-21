defmodule AponteWeb.ErrorHTML do
  @moduledoc """
  Páginas de erro minimalistas (404, 401, 500). Sem layout — auto-contidas
  para evitar dependência da camada que pode estar quebrada quando o erro
  acontece.
  """

  use AponteWeb, :html

  def render("404.html", assigns),
    do: page("404", "Essa página sumiu na pista.", assigns)

  def render("401.html", assigns), do: page("401", "Área só da equipe.", assigns)

  def render("500.html", assigns),
    do: page("500", "Algo quebrou aqui. Já estamos resolvendo.", assigns)

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)

  defp page(code, message, assigns) do
    # Plain merge (not Phoenix.Component.assign/3): this view is also rendered
    # from plugs (LoadOrg, UploadController) with conn.assigns, which has no
    # change-tracking metadata.
    assigns = Map.merge(assigns, %{code: code, message: message})

    ~H"""
    <!DOCTYPE html>
    <html lang="pt-br" style="--accent:#BF7262">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#FEF8DA" />
        <title>{"#{@code} — Aponte"}</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <link rel="stylesheet" href="/assets/css/app.css" />
      </head>
      <body class="bg-base text-fg text-sans">
        <main class="shell error-page stack-4">
          <img src="/images/aponte-logo.jpg" alt="Aponte" class="aponte-logo aponte-logo--hero" />
          <p class="text-2xl date-duo-time text-mono">{@code}</p>
          <p class="text-base text-muted">{@message}</p>
          <a href="/" class="btn btn--blob btn--block">Voltar pro início</a>
        </main>
      </body>
    </html>
    """
  end
end
