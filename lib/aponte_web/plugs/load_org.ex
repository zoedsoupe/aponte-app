defmodule AponteWeb.Plugs.LoadOrg do
  @moduledoc """
  Loads the tenant org from `conn.path_params["org_slug"]` into
  `assigns[:org]`. Unknown, reserved or suspended slugs get a 404 and halt.

  `call/2` (the `:load_org` pipeline) answers with the HTML error page;
  `load_org_api/2` (the `:load_org_api` pipeline) answers JSON for the
  `:client_api` scopes.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_root_layout: 2, put_view: 2, render: 2, json: 2]

  alias Aponte.Orgs

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case fetch_org(conn) do
      {:ok, org} ->
        # The gallery count rides on the org map so the tab bar (rendered by
        # the layout, which only receives @org) can hide the Galeria tab when
        # the org has no images. Cheap count query, once per org page.
        assign(conn, :org, Map.put(org, :gallery_count, Orgs.count_images(org.id)))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_root_layout(false)
        |> put_view(AponteWeb.ErrorHTML)
        |> render("404.html")
        |> halt()
    end
  end

  @doc "Function-plug variant for JSON pipelines: 404 as `{\"error\": ...}`."
  def load_org_api(conn, _opts) do
    case fetch_org(conn) do
      {:ok, org} ->
        assign(conn, :org, org)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not found"})
        |> halt()
    end
  end

  defp fetch_org(conn) do
    Orgs.get_org_by_slug(conn.path_params["org_slug"] || "")
  end
end
