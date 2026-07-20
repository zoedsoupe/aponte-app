defmodule Aponte.DjApplications do
  @moduledoc """
  Inscrições do "QUER TOCAR?" — DJs pedindo espaço pra tocar na SESH.
  Espelha o Google Form. Anti-spam (honeypot, tempo mínimo, rate limit) fica
  na camada web; aqui só persistência + push pro admin.
  """

  import Ecto.Query

  alias Aponte.{Notifications, Repo}
  alias Aponte.DjApplications.DjApplication
  alias Aponte.Orgs.Org

  @spec create(Org.t(), map()) :: {:ok, DjApplication.t()} | {:error, Ecto.Changeset.t()}
  def create(%Org{} = org, attrs) do
    attrs = put_org_id(attrs, org)

    case %DjApplication{} |> DjApplication.changeset(attrs) |> Repo.insert() do
      {:ok, application} = ok ->
        Notifications.notify_admin_dj_application(application)
        ok

      err ->
        err
    end
  end

  # org_id comes from the org argument, never from user params.
  defp put_org_id(attrs, %Org{id: id}) do
    if Enum.any?(Map.keys(attrs), &is_binary/1),
      do: Map.put(attrs, "org_id", id),
      else: Map.put(attrs, :org_id, id)
  end

  def change(%DjApplication{} = application \\ %DjApplication{}, attrs \\ %{}),
    do: DjApplication.changeset(application, attrs)

  @spec list(Ecto.UUID.t()) :: [DjApplication.t()]
  def list(org_id) do
    DjApplication
    |> where(org_id: ^org_id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> Repo.all()
  end
end
