defmodule Aponte.OrgsTest do
  use Aponte.DataCase, async: false

  import Aponte.Fixtures

  alias Aponte.Orgs
  alias Aponte.Orgs.{Org, OrgImage}

  defp org_attrs(overrides \\ %{}) do
    Map.merge(
      %{slug: "coletivo-#{System.unique_integer([:positive])}", name: "Coletivo"},
      overrides
    )
  end

  defp image_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        path: "abc123.webp",
        thumb_path: "abc123_thumb.webp",
        content_hash: "hash#{System.unique_integer([:positive])}",
        byte_size: 100
      },
      overrides
    )
  end

  describe "Org.changeset" do
    test "requires slug and name" do
      assert {:error, changeset} = Orgs.create_org(%{})
      assert %{slug: _, name: _} = errors_on(changeset)
    end

    test "downcases the slug" do
      assert {:ok, org} = Orgs.create_org(org_attrs(%{slug: "UPPER-Case1"}))
      assert org.slug == "upper-case1"
    end

    test "rejects invalid slug formats" do
      for slug <- ["a", "-abc", "ab_cd", "com espaço", "UPPER CASE!"] do
        assert {:error, changeset} = Orgs.create_org(org_attrs(%{slug: slug}))
        assert %{slug: _} = errors_on(changeset)
      end
    end

    test "rejects reserved slugs" do
      for slug <- ["admin", "sobre", "api", "uploads", "aponte"] do
        assert {:error, changeset} = Orgs.create_org(org_attrs(%{slug: slug}))
        assert %{slug: _} = errors_on(changeset)
      end
    end

    test "validates accent hex format" do
      assert {:error, changeset} = Orgs.create_org(org_attrs(%{accent_color: "pink"}))
      assert %{accent_color: _} = errors_on(changeset)

      assert {:ok, _} = Orgs.create_org(org_attrs(%{accent_color: "#9AA0A8"}))
    end

    test "validates theme color hex formats (bg/fg)" do
      assert {:error, changeset} = Orgs.create_org(org_attrs(%{bg_color: "dark"}))
      assert %{bg_color: _} = errors_on(changeset)

      assert {:error, changeset} = Orgs.create_org(org_attrs(%{fg_color: "#fff"}))
      assert %{fg_color: _} = errors_on(changeset)

      assert {:ok, org} =
               Orgs.create_org(org_attrs(%{bg_color: "#05070A", fg_color: "#F3F3F3"}))

      assert org.bg_color == "#05070A"
      assert org.fg_color == "#F3F3F3"
    end

    test "rejects a PIX copia-e-cola payload pasted as the key" do
      emv = "00020126360014br.gov.bcb.pix0114chave5204000053039865802BR"

      assert {:error, changeset} = Orgs.create_org(org_attrs(%{pix_key: emv}))
      assert %{pix_key: _} = errors_on(changeset)
    end

    test "trims whitespace around the pix key" do
      assert {:ok, org} = Orgs.create_org(org_attrs(%{pix_key: "  chave@pix.com  "}))
      assert org.pix_key == "chave@pix.com"
    end

    test "rejects a pix key longer than the BR Code field limit" do
      assert {:error, changeset} =
               Orgs.create_org(org_attrs(%{pix_key: String.duplicate("a", 78)}))

      assert %{pix_key: _} = errors_on(changeset)
    end

    test "social_links entries need non-empty label and url" do
      assert {:ok, org} =
               Orgs.create_org(
                 org_attrs(%{social_links: [%{"label" => "instagram", "url" => "https://ig/x"}]})
               )

      assert org.social_links == [%{"label" => "instagram", "url" => "https://ig/x"}]

      for links <- [
            [%{"label" => "", "url" => "https://ig/x"}],
            [%{"label" => "instagram", "url" => ""}],
            [%{"label" => "instagram"}],
            ["https://ig/x"]
          ] do
        assert {:error, changeset} = Orgs.create_org(org_attrs(%{social_links: links}))
        assert %{social_links: _} = errors_on(changeset)
      end
    end
  end

  describe "context" do
    test "create/get/update/change" do
      assert {:ok, org} = Orgs.create_org(org_attrs(%{name: "SESH"}))
      assert Orgs.get_org!(org.id).name == "SESH"

      assert {:ok, updated} = Orgs.update_org(org, %{name: "SESH LAB"})
      assert updated.name == "SESH LAB"

      assert %Ecto.Changeset{} = Orgs.change_org(org, %{name: "x"})
    end

    test "duplicate slug is a changeset error" do
      {:ok, org} = Orgs.create_org(org_attrs())
      assert {:error, changeset} = Orgs.create_org(org_attrs(%{slug: org.slug}))
      assert %{slug: _} = errors_on(changeset)
    end

    test "get_org_by_slug/1: unknown, reserved and suspended are not_found" do
      assert {:error, :not_found} = Orgs.get_org_by_slug("nope")
      assert {:error, :not_found} = Orgs.get_org_by_slug("admin")

      {:ok, org} = Orgs.create_org(org_attrs(%{slug: "ativa"}))
      assert {:ok, %Org{slug: "ativa"}} = Orgs.get_org_by_slug("ativa")

      {:ok, _suspended} = Orgs.update_org(org, %{status: :suspended})
      assert {:error, :not_found} = Orgs.get_org_by_slug("ativa")
    end

    test "list_active_orgs/0 excludes suspended" do
      {:ok, active} = Orgs.create_org(org_attrs())
      {:ok, suspended} = Orgs.create_org(org_attrs())
      {:ok, _} = Orgs.update_org(suspended, %{status: :suspended})

      slugs = Orgs.list_active_orgs() |> Enum.map(& &1.slug)
      assert active.slug in slugs
      refute suspended.slug in slugs
    end

    test "list_orgs_with_current_edition/0 zips orgs with their published edition" do
      alpha = org_fixture(%{slug: "alpha", name: "Alpha"})
      beta = org_fixture(%{slug: "beta", name: "Beta"})

      edition = edition_fixture(%{org_id: alpha.id, status: :published})
      _draft = edition_fixture(%{org_id: beta.id, status: :draft})

      result = Orgs.list_orgs_with_current_edition()

      # The migration-seeded "sesh" org is always present; assert per-org zip.
      assert {_, current} = Enum.find(result, fn {org, _} -> org.slug == "alpha" end)
      assert current.id == edition.id
      assert {_, nil} = Enum.find(result, fn {org, _} -> org.slug == "beta" end)
    end
  end

  describe "images" do
    test "add_image/2 appends at the next position and dedups on content hash" do
      org = org_fixture()

      {:ok, first} = Orgs.add_image(org, image_attrs(%{content_hash: "aaa"}))
      {:ok, second} = Orgs.add_image(org, image_attrs(%{content_hash: "bbb"}))

      assert first.position == 0
      assert second.position == 1

      assert {:error, :duplicate} = Orgs.add_image(org, image_attrs(%{content_hash: "aaa"}))
    end

    test "list_images/1 orders by position" do
      org = org_fixture()
      {:ok, _} = Orgs.add_image(org, image_attrs(%{content_hash: "aaa"}))
      {:ok, _} = Orgs.add_image(org, image_attrs(%{content_hash: "bbb"}))

      assert [%OrgImage{content_hash: "aaa"}, %OrgImage{content_hash: "bbb"}] =
               Orgs.list_images(org.id)
    end

    test "reorder_images/2 sets position = index" do
      org = org_fixture()
      {:ok, a} = Orgs.add_image(org, image_attrs(%{content_hash: "aaa"}))
      {:ok, b} = Orgs.add_image(org, image_attrs(%{content_hash: "bbb"}))

      assert :ok = Orgs.reorder_images(org.id, [b.id, a.id])

      assert [%OrgImage{id: b_id, position: 0}, %OrgImage{id: a_id, position: 1}] =
               Orgs.list_images(org.id)

      assert b_id == b.id
      assert a_id == a.id
    end

    test "delete_image/1 removes the row" do
      org = org_fixture()
      {:ok, image} = Orgs.add_image(org, image_attrs())

      assert {:ok, _} = Orgs.delete_image(image)
      assert Orgs.list_images(org.id) == []
    end
  end

  describe "quota" do
    test "over_quota?/3 boundary values" do
      # Exactly at quota is NOT over.
      refute Orgs.over_quota?(0, 100, 100)
      refute Orgs.over_quota?(100, 0, 100)
      # One byte past is over.
      assert Orgs.over_quota?(0, 101, 100)
      assert Orgs.over_quota?(100, 1, 100)
      # Empty quota.
      assert Orgs.over_quota?(0, 1, 0)
    end

    test "storage_used_bytes/1 sums image byte sizes" do
      org = org_fixture()
      assert Orgs.storage_used_bytes(org.id) == 0

      {:ok, _} = Orgs.add_image(org, image_attrs(%{byte_size: 300}))
      {:ok, _} = Orgs.add_image(org, image_attrs(%{byte_size: 200}))
      assert Orgs.storage_used_bytes(org.id) == 500
    end

    test "check_upload_quota/3: within, soft warning, hard enforced" do
      {:ok, org} = Orgs.create_org(org_attrs(%{storage_quota_bytes: 500}))
      {:ok, _} = Orgs.add_image(org, image_attrs(%{byte_size: 400}))

      assert {:ok, :within_quota} = Orgs.check_upload_quota(org, 100)
      # Soft by default: warns but allows.
      assert {:ok, :over_quota} = Orgs.check_upload_quota(org, 101)
      # Hard enforcement errors.
      assert {:error, :over_quota} = Orgs.check_upload_quota(org, 101, enforce?: true)
      assert {:ok, :within_quota} = Orgs.check_upload_quota(org, 100, enforce?: true)
    end
  end
end
