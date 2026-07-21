defmodule Aponte.ImagesVipsTest do
  @moduledoc """
  Integration test against the REAL libvips processor (`Aponte.Images.Vips`),
  not the Fake — guards the `Image.write/2` return-shape fix. Runs wherever
  vips is available (it is bundled via precompiled NIFs).
  """
  use ExUnit.Case, async: false

  alias Aponte.Images.Vips

  @moduletag :vips

  # 1x1 transparent PNG.
  @png_1px "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  setup do
    dir = Path.join(System.tmp_dir!(), "aponte_vips_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "process/3 writes web and thumb webp variants and sums their sizes", %{dir: dir} do
    source = Path.join(dir, "source.png")
    File.write!(source, Base.decode64!(@png_1px))

    assert {:ok, %{web: web, thumb: thumb, byte_size: byte_size}} =
             Vips.process(source, dir, "deadbeef")

    assert Path.basename(web) == "deadbeef.webp"
    assert Path.basename(thumb) == "deadbeef_thumb.webp"
    assert File.exists?(web)
    assert File.exists?(thumb)
    assert byte_size == File.stat!(web).size + File.stat!(thumb).size
    # The output is a real image vips can re-open (not a byte copy).
    assert {:ok, _image} = Image.open(web)
  end

  test "non-image input maps to {:error, :invalid_image}", %{dir: dir} do
    source = Path.join(dir, "not_an_image.png")
    File.write!(source, "definitely not an image")

    assert {:error, :invalid_image} = Vips.process(source, dir, "bad")
  end
end
