defmodule Aponte.Orgs do
  @moduledoc """
  Orgs are the tenant root: every edition, order, ticket, merch item and
  coupon belongs to one. Public URLs are `/:org_slug/...`; the slug is the
  identity, so a reserved list protects route literals from squatting.

  Gallery images live on disk under `Uploads.org_dir/1`; this context owns the
  metadata rows (position, byte_size) and the soft storage quota.
  """

  import Ecto.Query

  alias Aponte.Repo
  alias Aponte.Editions.Edition
  alias Aponte.Orgs.{Org, OrgImage}

  @reserved ~w(sobre admin api uploads dev assets images fonts live phoenix
               robots.txt sitemap.xml manifest.webmanifest sw.js favicon.ico aponte)

  @spec reserved_slugs() :: [String.t()]
  def reserved_slugs, do: @reserved

  @doc "Active org by slug. `{:error, :not_found}` for unknown, reserved or suspended."
  @spec get_org_by_slug(String.t()) :: {:ok, Org.t()} | {:error, :not_found}
  def get_org_by_slug(slug) when is_binary(slug) do
    slug = String.downcase(slug)

    if slug in @reserved do
      {:error, :not_found}
    else
      case Repo.get_by(Org, slug: slug, status: :active) do
        nil -> {:error, :not_found}
        %Org{} = org -> {:ok, org}
      end
    end
  end

  @spec get_org!(Ecto.UUID.t()) :: Org.t()
  def get_org!(id), do: Repo.get!(Org, id)

  @spec list_active_orgs() :: [Org.t()]
  def list_active_orgs do
    Org |> where(status: :active) |> order_by(asc: :name) |> Repo.all()
  end

  @doc """
  Every active org zipped with its current (published) edition, `nil` when it
  has none. Two queries total: orgs, then published editions grouped by org.
  """
  @spec list_orgs_with_current_edition() :: [{Org.t(), Edition.t() | nil}]
  def list_orgs_with_current_edition do
    orgs = list_active_orgs()
    org_ids = Enum.map(orgs, & &1.id)

    current_by_org =
      Edition
      |> where([e], e.status == :published and e.org_id in ^org_ids)
      |> order_by([e], desc: e.starts_at)
      |> Repo.all()
      |> Enum.group_by(& &1.org_id)
      |> Map.new(fn {org_id, [current | _]} -> {org_id, current} end)

    Enum.map(orgs, &{&1, Map.get(current_by_org, &1.id)})
  end

  @spec create_org(map()) :: {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
  def create_org(attrs) do
    %Org{} |> Org.changeset(attrs) |> Repo.insert()
  end

  @spec update_org(Org.t(), map()) :: {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
  def update_org(%Org{} = org, attrs) do
    org |> Org.changeset(attrs) |> Repo.update()
  end

  @spec change_org(Org.t(), map()) :: Ecto.Changeset.t()
  def change_org(%Org{} = org, attrs \\ %{}), do: Org.changeset(org, attrs)

  # ── Gallery ─────────────────────────────────────────────────────────────────

  @spec list_images(Ecto.UUID.t()) :: [OrgImage.t()]
  def list_images(org_id) do
    OrgImage
    |> where(org_id: ^org_id)
    |> order_by(asc: :position)
    |> Repo.all()
  end

  @doc """
  Inserts a gallery image. Re-uploading the same file (same content hash)
  returns `{:error, :duplicate}`. Position defaults to the end of the gallery.
  """
  @spec add_image(Org.t(), map()) ::
          {:ok, OrgImage.t()} | {:error, :duplicate | Ecto.Changeset.t()}
  def add_image(%Org{} = org, attrs) do
    attrs =
      attrs
      |> Map.put(:org_id, org.id)
      |> Map.put_new_lazy(:position, fn -> next_position(org.id) end)

    %OrgImage{}
    |> OrgImage.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, image} ->
        {:ok, image}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_violation?(changeset), do: {:error, :duplicate}, else: {:error, changeset}
    end
  end

  defp next_position(org_id) do
    Repo.one(
      from i in OrgImage, where: i.org_id == ^org_id, select: coalesce(max(i.position), -1)
    ) +
      1
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_msg, opts}} -> opts[:constraint] == :unique end)
  end

  @doc "Deletes the metadata row; the caller deletes the files from disk."
  @spec delete_image(OrgImage.t()) :: {:ok, OrgImage.t()}
  def delete_image(%OrgImage{} = image) do
    {:ok, _} = Repo.delete(image)
    {:ok, image}
  end

  @doc "Sets gallery order: position = index in `ids`, in one transaction."
  @spec reorder_images(Ecto.UUID.t(), [Ecto.UUID.t()]) :: :ok
  def reorder_images(org_id, ids) do
    Repo.transaction(fn ->
      ids
      |> Enum.with_index()
      |> Enum.each(fn {id, position} ->
        from(i in OrgImage, where: i.id == ^id and i.org_id == ^org_id)
        |> Repo.update_all(set: [position: position])
      end)
    end)

    :ok
  end

  # ── Quota ───────────────────────────────────────────────────────────────────

  @spec storage_used_bytes(Ecto.UUID.t()) :: non_neg_integer()
  def storage_used_bytes(org_id) do
    Repo.one(
      from i in OrgImage,
        where: i.org_id == ^org_id,
        select: coalesce(sum(i.byte_size), 0)
    )
  end

  @doc """
  Checks an incoming upload against the org's quota. Over-quota is a soft
  warning by default (`{:ok, :over_quota}`); `enforce?: true` hard-blocks with
  `{:error, :over_quota}`.
  """
  @spec check_upload_quota(Org.t(), non_neg_integer(), keyword()) ::
          {:ok, :within_quota} | {:ok, :over_quota} | {:error, :over_quota}
  def check_upload_quota(%Org{} = org, incoming_bytes, opts \\ []) do
    if over_quota?(storage_used_bytes(org.id), incoming_bytes, org.storage_quota_bytes) do
      if Keyword.get(opts, :enforce?, false), do: {:error, :over_quota}, else: {:ok, :over_quota}
    else
      {:ok, :within_quota}
    end
  end

  @doc "Pure check: is `used + incoming` over `quota`?"
  @spec over_quota?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def over_quota?(used_bytes, incoming_bytes, quota_bytes) do
    used_bytes + incoming_bytes > quota_bytes
  end
end
