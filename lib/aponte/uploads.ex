defmodule Aponte.Uploads do
  @moduledoc """
  Local-disk storage for user uploads (edition logos, merch images, org
  galleries). The root comes from `config :aponte, :uploads_dir` and accepts a
  plain path (`/data/uploads` in prod) or `{otp_app, "priv/path"}` (dev).
  Per-org dirs are created lazily at upload time.
  """

  @doc "Absolute path of the uploads root."
  @spec root() :: String.t()
  def root do
    case Application.get_env(:aponte, :uploads_dir, {:aponte, "priv/static/uploads"}) do
      path when is_binary(path) ->
        path

      {app, rel} ->
        Path.join(
          :code.priv_dir(app) |> to_string(),
          Path.relative_to_cwd(rel) |> String.replace_prefix("priv/", "")
        )
    end
  end

  @spec org_dir(Ecto.UUID.t()) :: String.t()
  def org_dir(org_id), do: Path.join([root(), "orgs", org_id])

  @spec ensure_dirs!() :: :ok
  def ensure_dirs! do
    File.mkdir_p!(root())
    :ok
  end

  @spec ensure_dirs!(Ecto.UUID.t()) :: :ok
  def ensure_dirs!(org_id) do
    File.mkdir_p!(org_dir(org_id))
    :ok
  end

  @doc "sha256 hex of a file, streamed (no full read into memory)."
  @spec content_hash(Path.t()) :: String.t()
  def content_hash(path) do
    path
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc "Deletes a file, ignoring missing-file errors. Always `:ok`."
  @spec delete_quiet(Path.t()) :: :ok
  def delete_quiet(path) do
    _ = File.rm(path)
    :ok
  end
end
