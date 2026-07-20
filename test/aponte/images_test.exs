defmodule Aponte.ImagesTest do
  use Aponte.DataCase, async: false

  alias Aponte.{Images, Uploads}

  test "test env uses the Fake processor (no vips needed)" do
    assert Application.fetch_env!(:aponte, :image_processor) == Aponte.Images.Fake
  end

  test "process/3 writes web and thumb variants and sums their sizes" do
    source = Path.join(Uploads.root(), "source.bin")
    File.write!(source, "fake image bytes")

    dest_dir = Uploads.org_dir(Ecto.UUID.generate())
    File.mkdir_p!(dest_dir)

    assert {:ok, %{web: web, thumb: thumb, byte_size: byte_size}} =
             Images.process(source, dest_dir, "abc123")

    assert Path.basename(web) == "abc123.webp"
    assert Path.basename(thumb) == "abc123_thumb.webp"
    assert File.read!(web) == "fake image bytes"
    assert File.read!(thumb) == "fake image bytes"
    assert byte_size == 2 * byte_size("fake image bytes")
  end

  test "content_hash/1 is the streamed sha256 hex of the file" do
    path = Path.join(Uploads.root(), "hash_me.txt")
    File.write!(path, "aponte")

    expected = :crypto.hash(:sha256, "aponte") |> Base.encode16(case: :lower)
    assert Uploads.content_hash(path) == expected
  end

  test "ensure_dirs!/1 creates the org dir; delete_quiet/1 ignores missing files" do
    org_id = Ecto.UUID.generate()
    assert :ok = Uploads.ensure_dirs!(org_id)
    assert File.dir?(Uploads.org_dir(org_id))

    assert :ok = Uploads.delete_quiet(Path.join(Uploads.root(), "missing.file"))
  end
end
