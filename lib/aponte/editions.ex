defmodule Aponte.Editions do
  @moduledoc """
  Edições da SESH e seus lotes de ingresso.

  No máximo uma edição `published` por vez — é ela que a landing exibe.
  A cor de accent da edição re-tematiza o site inteiro (CSS var `--accent`),
  e `logo_path` permite subir uma arte alternativa por edição.
  """

  import Ecto.Query

  alias Aponte.{Clock, Repo}
  alias Aponte.Editions.{Edition, EditionMerchItem, TicketType}
  alias Aponte.Orgs.Org
  alias Aponte.Tickets.{OrderItem, Ticket}

  # ── Queries ─────────────────────────────────────────────────────────────────

  @spec list_editions(Ecto.UUID.t()) :: [Edition.t()]
  def list_editions(org_id) do
    Edition
    |> where(org_id: ^org_id)
    |> order_by(desc: :number)
    |> Repo.all()
    |> Repo.preload(:ticket_types)
  end

  @doc "Edições visíveis nas páginas públicas (`published` + `past`) — rascunhos nunca vazam."
  @spec list_public_editions(Ecto.UUID.t()) :: [Edition.t()]
  def list_public_editions(org_id) do
    Edition
    |> where([e], e.org_id == ^org_id and e.status in [:published, :past])
    |> order_by(desc: :number)
    |> Repo.all()
    |> Repo.preload(:ticket_types)
  end

  @spec get_edition!(Ecto.UUID.t()) :: Edition.t()
  def get_edition!(id) do
    Edition |> Repo.get!(id) |> Repo.preload(:ticket_types)
  end

  @doc "Edição por id dentro da org — guarda contra URL-tampering cross-org."
  @spec get_edition_in_org(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Edition.t()} | {:error, :not_found}
  def get_edition_in_org(org_id, edition_id) do
    case Edition |> where(org_id: ^org_id) |> Repo.get(edition_id) do
      nil -> {:error, :not_found}
      %Edition{} = edition -> {:ok, Repo.preload(edition, :ticket_types)}
    end
  end

  @doc "Edição publicada da org (a que a landing mostra). `nil` se nenhuma."
  @spec current_edition(Ecto.UUID.t()) :: Edition.t() | nil
  def current_edition(org_id) do
    Edition
    |> where(status: :published, org_id: ^org_id)
    |> order_by(desc: :starts_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:ticket_types)
  end

  @doc "Só a cor de accent da edição publicada da org (query leve, p/ tematizar toda página). `nil` se nenhuma."
  @spec current_accent(Ecto.UUID.t()) :: String.t() | nil
  def current_accent(org_id) do
    Edition
    |> where(status: :published, org_id: ^org_id)
    |> order_by(desc: :starts_at)
    |> limit(1)
    |> select([e], e.accent_color)
    |> Repo.one()
  end

  @spec get_ticket_type!(Ecto.UUID.t()) :: TicketType.t()
  def get_ticket_type!(id), do: Repo.get!(TicketType, id)

  @doc "Ticket type by id, scoped to an edition (guards against cross-edition ids)."
  @spec get_ticket_type_in_edition(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, TicketType.t()} | {:error, :not_found}
  def get_ticket_type_in_edition(edition_id, id) do
    case Repo.get_by(TicketType, id: id, edition_id: edition_id) do
      nil -> {:error, :not_found}
      %TicketType{} = type -> {:ok, type}
    end
  end

  # ── Mutations ───────────────────────────────────────────────────────────────

  def change_edition(%Edition{} = edition, attrs \\ %{}), do: Edition.changeset(edition, attrs)

  @spec create_edition(Org.t(), map()) :: {:ok, Edition.t()} | {:error, Ecto.Changeset.t()}
  def create_edition(%Org{} = org, attrs) do
    attrs =
      attrs
      |> put_attr(:org_id, org.id)
      |> maybe_default_name(org)

    %Edition{} |> Edition.changeset(attrs) |> Repo.insert()
  end

  # Server-resolved values, never from user params. Accepts string- or
  # atom-keyed attrs (form vs context callers).
  defp put_attr(attrs, key, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1),
      do: Map.put(attrs, to_string(key), value),
      else: Map.put(attrs, key, value)
  end

  # Nome default "#{org.name} ##{n}" quando em branco (era hardcoded "SESH").
  defp maybe_default_name(attrs, %Org{} = org) do
    name = attrs[:name] || attrs["name"]
    number = attrs[:number] || attrs["number"]

    if name in [nil, ""] and number not in [nil, ""] do
      put_attr(attrs, :name, "#{org.name} ##{number}")
    else
      attrs
    end
  end

  def update_edition(%Edition{} = edition, attrs) do
    changeset =
      edition
      |> Repo.preload(:ticket_types)
      |> Edition.changeset(attrs)

    # Lotes com venda têm FK :restrict (pedidos/ingressos): apagar quebraria
    # histórico. Bloqueia a remoção e manda desativar em vez de excluir.
    case blocked_lote_deletions(changeset) do
      [] ->
        Repo.update(changeset)

      names ->
        changeset =
          Ecto.Changeset.add_error(
            changeset,
            :ticket_types,
            "lote(s) com venda não podem ser removidos, só desativados: #{Enum.join(names, ", ")}"
          )

        {:error, %{changeset | action: :update}}
    end
  end

  defp blocked_lote_deletions(changeset) do
    changeset
    |> Ecto.Changeset.get_change(:ticket_types, [])
    |> Enum.filter(&(&1.action in [:replace, :delete] and ticket_type_referenced?(&1.data.id)))
    |> Enum.map(& &1.data.name)
  end

  defp ticket_type_referenced?(nil), do: false

  defp ticket_type_referenced?(id) do
    Repo.exists?(from o in OrderItem, where: o.ticket_type_id == ^id) or
      Repo.exists?(from t in Ticket, where: t.ticket_type_id == ^id)
  end

  @doc """
  Publica a edição, despublicando qualquer outra (`published -> past`).
  Broadcast em `"editions"` pra UI reagir.
  """
  @spec publish(Edition.t()) :: {:ok, Edition.t()} | {:error, Ecto.Changeset.t()}
  def publish(%Edition{} = edition) do
    Repo.transaction(fn ->
      from(e in Edition,
        where: e.status == :published and e.id != ^edition.id and e.org_id == ^edition.org_id
      )
      |> Repo.update_all(set: [status: :past, updated_at: Clock.now_utc()])

      case edition |> Ecto.Changeset.change(status: :published) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
    |> case do
      {:ok, updated} ->
        broadcast({:edition_published, updated.id})
        {:ok, updated}

      err ->
        err
    end
  end

  @spec archive(Edition.t()) :: {:ok, Edition.t()} | {:error, Ecto.Changeset.t()}
  def archive(%Edition{} = edition) do
    edition |> Ecto.Changeset.change(status: :past) |> Repo.update()
  end

  defp broadcast(msg) do
    Phoenix.PubSub.broadcast(Aponte.PubSub, "editions", msg)
  end

  # ── Merch em destaque por edição ────────────────────────────────────────────

  @doc "IDs de merch destacados numa edicao."
  @spec featured_merch_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def featured_merch_ids(edition_id) do
    from(e in EditionMerchItem, where: e.edition_id == ^edition_id, select: e.merch_item_id)
    |> Repo.all()
  end

  @doc "Substitui o conjunto de merch destacado de uma edicao (delete-all + insert)."
  @spec set_featured_merch(Ecto.UUID.t(), [Ecto.UUID.t()]) :: :ok
  def set_featured_merch(edition_id, merch_item_ids) do
    now = Clock.now_utc() |> DateTime.to_naive()

    Repo.transaction(fn ->
      from(e in EditionMerchItem, where: e.edition_id == ^edition_id) |> Repo.delete_all()

      rows =
        Enum.map(merch_item_ids, fn id ->
          %{edition_id: edition_id, merch_item_id: id, inserted_at: now}
        end)

      if rows != [], do: Repo.insert_all(EditionMerchItem, rows)
    end)

    :ok
  end

  # ── Uploads (logo por edição) ───────────────────────────────────────────────

  @doc """
  Diretório no disco onde logos de edição são salvos.

  Aceita binário (`/data/uploads` em prod) ou `{otp_app, "priv/path"}` (dev).
  """
  @spec uploads_dir() :: String.t()
  def uploads_dir do
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

  @spec editions_dir() :: String.t()
  def editions_dir, do: Path.join(uploads_dir(), "editions")

  @spec ensure_uploads_dir!() :: :ok
  def ensure_uploads_dir! do
    File.mkdir_p!(editions_dir())
    :ok
  end

  @spec logo_url(String.t() | nil) :: String.t() | nil
  def logo_url(nil), do: nil
  def logo_url(filename), do: "/uploads/editions/" <> filename
end
