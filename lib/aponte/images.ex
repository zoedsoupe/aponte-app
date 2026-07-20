defmodule Aponte.Images do
  @moduledoc """
  Entry point for image processing. Delegates to the configured
  `Aponte.Images.Processor` impl (`config :aponte, :image_processor`).
  """

  alias Aponte.Images.Processor

  @spec process(Path.t(), Path.t(), String.t()) :: {:ok, Processor.result()} | {:error, term()}
  def process(source_path, dest_dir, basename) do
    processor().process(source_path, dest_dir, basename)
  end

  defp processor, do: Application.fetch_env!(:aponte, :image_processor)
end
