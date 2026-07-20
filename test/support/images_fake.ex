defmodule Aponte.Images.Fake do
  @moduledoc """
  Test-double processor: copies the source bytes to both variant paths (no
  vips needed) and returns the same shape as the real impl.
  """

  @behaviour Aponte.Images.Processor

  @impl true
  def process(source_path, dest_dir, basename) do
    web = Path.join(dest_dir, basename <> ".webp")
    thumb = Path.join(dest_dir, basename <> "_thumb.webp")

    File.cp!(source_path, web)
    File.cp!(source_path, thumb)

    {:ok, %{web: web, thumb: thumb, byte_size: file_size(web) + file_size(thumb)}}
  end

  defp file_size(path), do: File.stat!(path).size
end
