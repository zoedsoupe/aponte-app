defmodule AponteWeb.UploadController do
  @moduledoc """
  Serves user uploads (edition logos, merch images, org galleries) straight
  from `Uploads.root/0` with immutable long-cache headers. Replaces the old
  `Plug.Static, at: "/uploads"`, which could not set cache headers. Lives
  outside `:browser` — plain GETs need no session/CSRF.
  """

  use AponteWeb, :controller

  alias Aponte.Uploads

  @cache_control "public, max-age=31536000, immutable"

  def show(conn, %{"path" => segments}) do
    if Enum.any?(segments, &(&1 in ["..", ""])) do
      not_found(conn)
    else
      path = Path.join([Uploads.root() | segments])

      if File.regular?(path) do
        conn
        |> put_resp_header("cache-control", @cache_control)
        |> put_resp_content_type(MIME.from_path(path))
        |> send_file(200, path)
      else
        not_found(conn)
      end
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_root_layout(false)
    |> put_view(AponteWeb.ErrorHTML)
    |> render("404.html")
    |> halt()
  end
end
