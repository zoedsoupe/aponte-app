defmodule AponteWeb.Plugs.RedirectLegacyHost do
  @moduledoc """
  Endpoint plug (before the router): answers requests that arrive on a legacy
  host with a redirect to its canonical replacement, preserving path + query.

  Config (prod only; empty map disables the plug):

      config :aponte, :legacy_host_redirects, %{"sesh-lab.fly.dev" => "aponte.fly.dev"}
      config :aponte, :legacy_host_status, 301

  Flip the status to 410 once the redirect window closes (SPEC_APONTE_V1
  section 6), then remove the config and this plug.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    redirects = Application.get_env(:aponte, :legacy_host_redirects, %{})

    case Map.fetch(redirects, conn.host) do
      :error ->
        conn

      {:ok, target} ->
        conn
        |> put_resp_header("location", location(target, conn))
        |> send_resp(status(), "")
        |> halt()
    end
  end

  defp location(target, conn) do
    query = if conn.query_string == "", do: "", else: "?#{conn.query_string}"
    "https://#{target}#{conn.request_path}#{query}"
  end

  defp status do
    case Application.get_env(:aponte, :legacy_host_status, 301) do
      410 -> 410
      _ -> 301
    end
  end
end
