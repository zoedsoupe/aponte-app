defmodule AponteWeb.UploadControllerTest do
  use AponteWeb.ConnCase, async: false

  alias Aponte.Uploads

  test "serves an existing file with immutable long-cache headers", %{conn: conn} do
    path = Path.join([Uploads.root(), "editions", "flyer.txt"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "flyer bytes")

    conn = get(conn, "/uploads/editions/flyer.txt")

    assert response(conn, 200) == "flyer bytes"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/plain"
  end

  test "sandboxes served SVGs to neutralize stored script", %{conn: conn} do
    path = Path.join([Uploads.root(), "editions", "logo.svg"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "<svg xmlns='http://www.w3.org/2000/svg'></svg>")

    conn = get(conn, "/uploads/editions/logo.svg")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-security-policy") == ["sandbox"]
  end

  test "does not sandbox non-SVG uploads", %{conn: conn} do
    path = Path.join([Uploads.root(), "editions", "plain.txt"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "x")

    conn = get(conn, "/uploads/editions/plain.txt")

    assert get_resp_header(conn, "content-security-policy") == []
  end

  test "rejects path traversal", %{conn: conn} do
    conn = get(conn, "/uploads/../mix.exs")
    assert response(conn, 404)
  end

  test "404s on missing file", %{conn: conn} do
    conn = get(conn, "/uploads/editions/nope.png")
    assert response(conn, 404)
  end
end
