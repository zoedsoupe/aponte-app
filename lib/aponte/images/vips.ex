defmodule Aponte.Images.Vips do
  @moduledoc """
  libvips-backed processor (via the `image` package). Writes `<basename>.webp`
  (1600px) and `<basename>_thumb.webp` (400px) into `dest_dir`; `byte_size` is
  the sum of both files on disk. Non-image input maps to
  `{:error, :invalid_image}`.
  """

  @behaviour Aponte.Images.Processor

  @web_width 1600
  @thumb_width 400

  @impl true
  def process(source_path, dest_dir, basename) do
    with {:ok, image} <- open(source_path),
         {:ok, web} <- write_variant(image, dest_dir, basename <> ".webp", @web_width),
         {:ok, thumb} <- write_variant(image, dest_dir, basename <> "_thumb.webp", @thumb_width) do
      {:ok, %{web: web, thumb: thumb, byte_size: file_size(web) + file_size(thumb)}}
    end
  end

  defp open(path) do
    case Image.open(path) do
      {:ok, image} -> {:ok, image}
      {:error, _} -> {:error, :invalid_image}
    end
  end

  defp write_variant(image, dest_dir, filename, width) do
    path = Path.join(dest_dir, filename)

    # image ~> 0.71: Image.write/2 returns {:ok, image}, not :ok.
    with {:ok, resized} <- Image.thumbnail(image, width),
         {:ok, _written} <- Image.write(resized, path) do
      {:ok, path}
    end
  end

  defp file_size(path), do: File.stat!(path).size
end
