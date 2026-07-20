defmodule Aponte.Editions.Edition do
  use Ecto.Schema
  import Ecto.Changeset

  alias Aponte.Editions.TicketType

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "editions" do
    belongs_to :org, Aponte.Orgs.Org

    field :number, :integer
    field :name, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :venue, :string
    field :venue_address, :string
    # Um nome por linha, renderizado como lista no flyer.
    field :lineup, :string

    field :status, Ecto.Enum,
      values: [:draft, :published, :past],
      default: :draft

    field :accent_color, :string, default: "#F07BC0"
    field :logo_path, :string

    has_many :ticket_types, TicketType, preload_order: [asc: :position], on_replace: :delete

    timestamps()
  end

  @castable ~w(org_id number name starts_at ends_at venue venue_address lineup status
               accent_color logo_path)a
  @required ~w(org_id number name starts_at venue)a

  def changeset(edition, attrs) do
    edition
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_number(:number, greater_than: 0)
    |> validate_format(:accent_color, ~r/^#[0-9a-fA-F]{6}$/, message: "use formato hex #RRGGBB")
    |> validate_ends_after_starts()
    |> cast_assoc(:ticket_types,
      with: &TicketType.changeset/2,
      sort_param: :ticket_types_sort,
      drop_param: :ticket_types_drop
    )
    |> unique_constraint([:org_id, :number])
  end

  defp validate_ends_after_starts(changeset) do
    case {get_field(changeset, :starts_at), get_field(changeset, :ends_at)} do
      {%DateTime{} = starts_at, %DateTime{} = ends_at} ->
        if DateTime.compare(ends_at, starts_at) == :gt do
          changeset
        else
          add_error(changeset, :ends_at, "deve ser depois do início")
        end

      _ ->
        changeset
    end
  end

  @doc "Lineup como lista de nomes (uma linha por atração)."
  @spec lineup_list(t()) :: [String.t()]
  def lineup_list(%__MODULE__{lineup: nil}), do: []

  def lineup_list(%__MODULE__{lineup: lineup}) do
    lineup
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
