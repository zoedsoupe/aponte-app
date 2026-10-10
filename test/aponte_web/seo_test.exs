defmodule AponteWeb.SEOTest do
  use ExUnit.Case, async: true

  alias AponteWeb.SEO

  describe "music_event_jsonld/3" do
    test "organizer name is the org name" do
      edition = %{
        name: "SESH #9",
        starts_at: ~U[2026-08-01 22:00:00Z],
        venue: "OCA ROOTS",
        venue_address: nil
      }

      decoded = edition |> SEO.music_event_jsonld(nil, "SESH") |> JSON.decode!()

      assert decoded["@type"] == "MusicEvent"
      assert decoded["organizer"] == %{"@type" => "Organization", "name" => "SESH"}
      assert decoded["startDate"] == "2026-08-01T22:00:00Z"
    end

    test "escapes < so a name cannot break out of the script tag" do
      edition = %{
        name: "rolê </script><script>alert(1)</script>",
        starts_at: nil,
        venue: "OCA",
        venue_address: nil
      }

      json = SEO.music_event_jsonld(edition, nil, "SESH")

      refute json =~ "<"
      assert JSON.decode!(json)["name"] == "rolê </script><script>alert(1)</script>"
    end

    test "nil edition renders nothing" do
      assert SEO.music_event_jsonld(nil, nil, "SESH") == nil
    end
  end
end
