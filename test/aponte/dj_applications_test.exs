defmodule Aponte.DjApplicationsTest do
  use Aponte.DataCase, async: false

  import Aponte.Fixtures

  alias Aponte.DjApplications

  @valid %{
    "name" => "DJ Fulano",
    "whatsapp" => "(22) 99999-8888",
    "instagram" => "@FulanoDJ",
    "musical_styles" => "techno, IDM, breakcore",
    "about" => "comecei mês passado, quero testar um set"
  }

  test "create/2 persists, normalizing whatsapp + instagram" do
    org = org_fixture()
    assert {:ok, app} = DjApplications.create(org, @valid)
    assert app.whatsapp == "22999998888"
    assert app.instagram == "fulanodj"
    assert app.musical_styles =~ "techno"
    assert app.org_id == org.id
  end

  test "create/2 requires all fields" do
    assert {:error, cs} = DjApplications.create(org_fixture(), %{"name" => "x"})
    errors = errors_on(cs)
    assert errors.whatsapp
    assert errors.instagram
    assert errors.musical_styles
    assert errors.about
  end

  test "list/1 returns newest first" do
    org = org_fixture()
    {:ok, _} = DjApplications.create(org, %{@valid | "name" => "DJ Um"})
    {:ok, _} = DjApplications.create(org, %{@valid | "name" => "DJ Dois"})
    assert ["DJ Dois", "DJ Um"] = DjApplications.list(org.id) |> Enum.map(& &1.name)
  end
end
