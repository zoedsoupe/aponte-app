defmodule AponteWeb.SEO do
  @moduledoc "Defaults + builders for meta/OG/Twitter/JSON-LD. Pure core."

  @site_name "Aponte"
  @default_desc "Aponte: os rolês de Campos dos Goytacazes num lugar só. Festa, expo e ingresso direto com quem faz o rolê, sem taxa."

  @type meta :: %{
          title: String.t(),
          description: String.t(),
          image: String.t() | nil,
          url: String.t(),
          type: String.t(),
          site_name: String.t(),
          no_index: boolean()
        }

  @spec site_name() :: String.t()
  def site_name, do: @site_name

  @doc "Builds the meta map from per-page assigns, filling sane defaults."
  @spec build(map(), String.t()) :: meta()
  def build(assigns, request_url) do
    %{
      title: assigns[:page_title] || @site_name,
      description: assigns[:seo_description] || @default_desc,
      image: assigns[:seo_image],
      url: assigns[:seo_url] || request_url,
      type: assigns[:seo_type] || "website",
      site_name: @site_name,
      no_index: assigns[:no_index] || false
    }
  end

  @doc "Makes a path absolute against the endpoint host. Passes through nil/absolute."
  @spec abs_url(String.t() | nil) :: String.t() | nil
  def abs_url(nil), do: nil
  def abs_url("http" <> _ = url), do: url
  def abs_url(path), do: AponteWeb.Endpoint.url() <> path

  @doc "MusicEvent JSON-LD for the current edition. nil if no edition. Pure."
  @spec music_event_jsonld(map() | nil, String.t() | nil, String.t()) :: String.t() | nil
  def music_event_jsonld(nil, _url, _org_name), do: nil

  def music_event_jsonld(edition, image_url, org_name) do
    %{
      "@context" => "https://schema.org",
      "@type" => "MusicEvent",
      "name" => edition.name,
      "startDate" => edition.starts_at && DateTime.to_iso8601(edition.starts_at),
      "location" => %{
        "@type" => "Place",
        "name" => edition.venue,
        "address" => edition.venue_address
      },
      "image" => image_url,
      "organizer" => %{"@type" => "Organization", "name" => org_name}
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> JSON.encode!()
    # JSON.encode! does not escape "<", so a name/venue containing "</script>"
    # would break out of the JSON-LD script tag. \u003c is valid inside JSON
    # strings and closes the hole.
    |> String.replace("<", "\\u003c")
  end
end
