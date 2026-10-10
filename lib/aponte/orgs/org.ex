defmodule Aponte.Orgs.Org do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orgs" do
    field :slug, :string
    field :name, :string
    field :about, :string
    field :accent_color, :string, default: "#F07BC0"
    field :bg_color, :string
    field :fg_color, :string
    field :logo_path, :string
    field :instagram, :string
    field :pix_key, :string
    field :status, Ecto.Enum, values: [:active, :suspended], default: :active
    field :tier, Ecto.Enum, values: [:free, :paid], default: :free
    field :storage_quota_bytes, :integer, default: 52_428_800
    field :social_links, {:array, :map}, default: []

    has_many :editions, Aponte.Editions.Edition
    has_many :images, Aponte.Orgs.OrgImage

    timestamps()
  end

  @castable ~w(slug name about accent_color bg_color fg_color logo_path instagram pix_key
               status tier storage_quota_bytes social_links)a
  @required ~w(slug name)a

  def changeset(org, attrs) do
    org
    |> cast(attrs, @castable)
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:pix_key, &trim_pix_key/1)
    |> validate_required(@required)
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]{1,31}$/,
      message: "use letras minúsculas, números ou hífen"
    )
    |> validate_reserved_slug()
    |> validate_format(:accent_color, ~r/^#[0-9a-fA-F]{6}$/, message: "use formato hex #RRGGBB")
    |> validate_format(:bg_color, ~r/^#[0-9a-fA-F]{6}$/, message: "use formato hex #RRGGBB")
    |> validate_format(:fg_color, ~r/^#[0-9a-fA-F]{6}$/, message: "use formato hex #RRGGBB")
    |> validate_social_links()
    |> validate_pix_key()
    # 77 is the BR Code max for the key field (01); longer keys overflow the
    # 2-digit TLV length and corrupt the EMV silently.
    |> validate_length(:pix_key, max: 77, message: "chave PIX longa demais pro BR Code")
    |> unique_constraint(:slug)
  end

  defp normalize_slug(nil), do: nil
  defp normalize_slug(slug), do: String.downcase(slug)

  defp trim_pix_key(nil), do: nil
  defp trim_pix_key(key), do: String.trim(key)

  defp validate_reserved_slug(changeset) do
    validate_change(changeset, :slug, fn :slug, slug ->
      if slug in Aponte.Orgs.reserved_slugs(), do: [slug: "slug reservado"], else: []
    end)
  end

  # Um "copia e cola" do PIX é o EMV BR Code inteiro, não uma chave. Colar isso
  # no campo gera um QR inválido silenciosamente (a chave real vai embrulhada
  # dentro do payload e o app do banco lê lixo). Aqui barra só o formato do
  # payload; a chave em si (CPF, CNPJ, celular, email, EVP) passa.
  defp validate_pix_key(changeset) do
    validate_change(changeset, :pix_key, fn :pix_key, key ->
      if emv_payload?(key),
        do: [pix_key: "isso é o código copia-e-cola do PIX, não a chave"],
        else: []
    end)
  end

  defp emv_payload?(key) when is_binary(key) do
    String.starts_with?(key, "000201") or String.contains?(key, "br.gov.bcb.pix")
  end

  defp emv_payload?(_), do: false

  # Every entry must be a map with non-empty "label" and "url" keys.
  defp validate_social_links(changeset) do
    validate_change(changeset, :social_links, fn :social_links, links ->
      if Enum.all?(links, &valid_social_link?/1) do
        []
      else
        [social_links: "cada link precisa de label e url não vazios"]
      end
    end)
  end

  defp valid_social_link?(%{"label" => label, "url" => url})
       when is_binary(label) and is_binary(url) and label != "" and url != "",
       do: true

  defp valid_social_link?(_), do: false
end
