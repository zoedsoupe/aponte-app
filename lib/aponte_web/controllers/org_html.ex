defmodule AponteWeb.OrgHTML do
  @moduledoc false
  use AponteWeb, :html

  import AponteWeb.PageHTML,
    only: [edition_logo: 1, edition_day: 1, edition_time: 1, lineup_lines: 1]

  embed_templates "org_html/*"

  @doc "Public URL of a gallery file stored under the org's uploads dir."
  def image_url(org, filename), do: "/uploads/orgs/#{org.id}/#{filename}"

  @doc "Public URL of the org's uploaded logo, `nil` when unset."
  def logo_url(%{logo_path: nil}), do: nil
  def logo_url(org), do: image_url(org, org.logo_path)

  @doc "About text split into paragraphs (one per non-empty line)."
  def about_paragraphs(nil), do: []

  def about_paragraphs(text) do
    text |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)
  end

  @doc """
  First invalid DJ form field, in form order. Only set on a failed submit
  (`changeset.action`), so a fresh form never steals focus.
  """
  def dj_first_invalid(%{action: nil}), do: nil

  def dj_first_invalid(changeset) do
    Enum.find(~w(name whatsapp instagram musical_styles about)a, fn field ->
      Keyword.has_key?(changeset.errors, field)
    end)
  end

  @doc ~S|Handle de exibição com @: "coletivo.sesh" -> "@coletivo.sesh".|
  def instagram_handle(handle) do
    "@" <> (handle |> String.trim() |> String.trim_leading("@"))
  end

  @doc """
  Org identity artwork for org pages. Chain: edition logo -> org logo ->
  org name as an Archivo Expanded wordmark. The SESH vector only renders for
  SESH itself (it is that org's actual logo) — it is never a fallback for
  other orgs.
  """
  attr :org, :map, required: true
  attr :edition, :map, default: nil
  attr :class, :string, default: nil

  def org_logo(assigns) do
    assigns = assign(assigns, :src, identity_src(assigns.org, assigns.edition))

    ~H"""
    <%= cond do %>
      <% @src -> %>
        <.sesh_logo src={@src} alt={identity_alt(@org, @edition)} class={@class} />
      <% @org.slug == "sesh" -> %>
        <.sesh_logo class={@class} />
      <% true -> %>
        <span class={["org-wordmark", @class]}>{@org.name}</span>
    <% end %>
    """
  end

  defp identity_src(org, nil), do: logo_url(org)
  defp identity_src(org, edition), do: edition_logo(edition) || logo_url(org)

  defp identity_alt(org, edition) do
    if edition && edition_logo(edition), do: edition.name, else: org.name
  end
end
