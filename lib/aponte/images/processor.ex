defmodule Aponte.Images.Processor do
  @moduledoc """
  Behaviour for turning one uploaded file into the gallery variants (1600px
  web webp + 400px thumb webp). The real impl is libvips-backed
  (`Aponte.Images.Vips`); tests use `Aponte.Images.Fake` so the suite runs
  without vips.
  """

  @type result :: %{web: String.t(), thumb: String.t(), byte_size: non_neg_integer()}

  @callback process(
              source_path :: Path.t(),
              dest_dir :: Path.t(),
              basename :: String.t()
            ) :: {:ok, result()} | {:error, term()}
end
