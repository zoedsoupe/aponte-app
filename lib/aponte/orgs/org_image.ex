defmodule Aponte.Orgs.OrgImage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aponte.Orgs.Org

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "org_images" do
    belongs_to :org, Org

    field :path, :string
    field :thumb_path, :string
    field :original_filename, :string
    field :content_hash, :string
    field :position, :integer, default: 0
    field :byte_size, :integer

    timestamps(updated_at: false)
  end

  @castable ~w(org_id path thumb_path original_filename content_hash position byte_size)a
  @required ~w(org_id path thumb_path content_hash byte_size)a

  def changeset(image, attrs) do
    image
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> unique_constraint([:org_id, :content_hash])
  end
end
