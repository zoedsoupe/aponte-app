defmodule AponteWeb.OrgHTML do
  @moduledoc false
  use AponteWeb, :html

  import AponteWeb.PageHTML,
    only: [edition_logo: 1, edition_day: 1, edition_time: 1, lineup_lines: 1]

  embed_templates "org_html/*"

  @doc "Public URL of a gallery file stored under the org's uploads dir."
  def image_url(org, filename), do: "/uploads/orgs/#{org.id}/#{filename}"

  @doc "About text split into paragraphs (one per non-empty line)."
  def about_paragraphs(nil), do: []

  def about_paragraphs(text) do
    text |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)
  end

  @doc ~S|Handle de exibição com @: "coletivo.sesh" -> "@coletivo.sesh".|
  def instagram_handle(handle) do
    "@" <> (handle |> String.trim() |> String.trim_leading("@"))
  end
end
