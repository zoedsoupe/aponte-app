defmodule AponteWeb.Admin.OrgGalleryLiveTest do
  use AponteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Aponte.{Orgs, Uploads}

  setup do
    cfg = Application.fetch_env!(:aponte, :admin_auth)
    auth = "Basic " <> Base.encode64("#{cfg[:username]}:#{cfg[:password]}")
    {:ok, org} = Orgs.get_org_by_slug("sesh")
    %{auth: auth, org: org}
  end

  defp authed(conn, auth), do: put_req_header(conn, "authorization", auth)

  defp upload(view, name, content) do
    file =
      file_input(view, "#gallery-form", :images, [
        %{name: name, content: content, size: byte_size(content), type: "image/jpeg"}
      ])

    render_upload(file, name)
  end

  test "upload flow inserts gallery rows (Fake processor)", %{conn: conn, auth: auth, org: org} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/galeria")

    upload(view, "festa.jpg", "foto bytes 1")
    html = view |> form("#gallery-form") |> render_submit()

    assert html =~ "1 imagem(ns) adicionada(s)."

    assert [image] = Orgs.list_images(org.id)
    assert image.original_filename == "festa.jpg"
    assert image.position == 0

    expected_hash =
      :crypto.hash(:sha256, "foto bytes 1") |> Base.encode16(case: :lower)

    assert image.content_hash == expected_hash
    assert File.exists?(Path.join(Uploads.org_dir(org.id), image.path))
    assert File.exists?(Path.join(Uploads.org_dir(org.id), image.thumb_path))
  end

  test "re-uploading the same file flashes the duplicate message", %{
    conn: conn,
    auth: auth,
    org: org
  } do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/galeria")

    upload(view, "festa.jpg", "mesmos bytes")
    view |> form("#gallery-form") |> render_submit()

    upload(view, "festa2.jpg", "mesmos bytes")
    html = view |> form("#gallery-form") |> render_submit()

    assert html =~ "imagem ja enviada"
    assert length(Orgs.list_images(org.id)) == 1
  end

  test "over-quota upload still inserts and flashes the soft warning", %{
    conn: conn,
    auth: auth,
    org: org
  } do
    {:ok, org} = Orgs.update_org(org, %{storage_quota_bytes: 1})

    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/galeria")

    upload(view, "festa.jpg", "qualquer coisa")
    html = view |> form("#gallery-form") |> render_submit()

    assert html =~ "quota de armazenamento"
    assert length(Orgs.list_images(org.id)) == 1
  end

  test "delete removes the row and the files", %{conn: conn, auth: auth, org: org} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/galeria")

    upload(view, "festa.jpg", "pra apagar")
    view |> form("#gallery-form") |> render_submit()

    [image] = Orgs.list_images(org.id)
    web = Path.join(Uploads.org_dir(org.id), image.path)

    view
    |> element(~s|button[phx-click="delete"][phx-value-id="#{image.id}"]|)
    |> render_click()

    assert Orgs.list_images(org.id) == []
    refute File.exists?(web)
  end

  test "up/down buttons reorder positions", %{conn: conn, auth: auth, org: org} do
    {:ok, view, _html} = conn |> authed(auth) |> live(~p"/admin/sesh/galeria")

    upload(view, "a.jpg", "bytes a")
    upload(view, "b.jpg", "bytes b")
    upload(view, "c.jpg", "bytes c")
    view |> form("#gallery-form") |> render_submit()

    # Consume order follows entry order, not file_input order — assert against
    # whatever the initial positions are.
    assert [x, y, z] = Orgs.list_images(org.id)
    assert [x.position, y.position, z.position] == [0, 1, 2]

    view
    |> element(~s|button[phx-click="move"][phx-value-id="#{y.id}"][phx-value-dir="up"]|)
    |> render_click()

    assert [first, second, third] = Orgs.list_images(org.id)
    assert [first.id, second.id, third.id] == [y.id, x.id, z.id]
    assert [first.position, second.position, third.position] == [0, 1, 2]

    view
    |> element(~s|button[phx-click="move"][phx-value-id="#{first.id}"][phx-value-dir="down"]|)
    |> render_click()

    assert [first, _, _] = Orgs.list_images(org.id)
    assert first.id == x.id
  end
end
