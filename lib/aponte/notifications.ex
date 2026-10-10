defmodule Aponte.Notifications do
  @moduledoc """
  Public API for admin Web Push notifications.

  Stores push subscriptions, fans out notifications across all registered
  devices in unlinked tasks (so order creation latency isn't affected by push
  service round-trips), and prunes subscriptions the push service reports as
  gone (HTTP 404/410).
  """

  import Ecto.Query
  require Logger

  alias Aponte.{Clock, Repo}
  alias Aponte.Editions.{Edition, TicketType}
  alias Aponte.Orgs.Org
  alias Aponte.Tickets.Order
  alias Aponte.Notifications.PushSubscription

  # ── Subscriptions ──────────────────────────────────────────────────────────

  # A device holds one subscription per (audience, org): subscribing under a
  # second org adds a row instead of overwriting the first. COALESCE collapses
  # the NULL org of admin / Aponte-wide subs so they still dedupe by endpoint.
  @spec subscribe(map()) :: {:ok, PushSubscription.t()} | {:error, Ecto.Changeset.t()}
  def subscribe(attrs) do
    %PushSubscription{}
    |> PushSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace, [:org_id, :p256dh, :auth, :user_agent, :audience, :topics, :updated_at]},
      conflict_target: {:unsafe_fragment, "(endpoint, audience, COALESCE(org_id, ''))"},
      returning: true
    )
  end

  @doc "Drops every row for an endpoint (device gone), across orgs and audiences."
  @spec unsubscribe(endpoint :: String.t()) :: :ok
  def unsubscribe(endpoint) do
    PushSubscription
    |> where(endpoint: ^endpoint)
    |> Repo.delete_all()

    :ok
  end

  @doc "Drops only the given device's subscription for one audience/org."
  @spec unsubscribe(endpoint :: String.t(), :admin | :client, Ecto.UUID.t() | nil) :: :ok
  def unsubscribe(endpoint, audience, org_id) do
    PushSubscription
    |> where(endpoint: ^endpoint)
    |> where(audience: ^audience)
    |> for_org(org_id)
    |> Repo.delete_all()

    :ok
  end

  @doc "Returns the opt-in topics for a client subscription by endpoint + org."
  @spec get_client_topics(endpoint :: String.t(), Ecto.UUID.t() | nil) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def get_client_topics(endpoint, org_id) do
    case client_sub(endpoint, org_id) do
      nil -> {:error, :not_found}
      %PushSubscription{topics: topics} -> {:ok, topics || []}
    end
  end

  @doc "Updates the opt-in topics of a client subscription (config panel)."
  @spec update_topics(endpoint :: String.t(), Ecto.UUID.t() | nil, [String.t()]) ::
          {:ok, PushSubscription.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_topics(endpoint, org_id, topics) when is_list(topics) do
    case client_sub(endpoint, org_id) do
      nil -> {:error, :not_found}
      sub -> sub |> PushSubscription.changeset(%{topics: topics}) |> Repo.update()
    end
  end

  # The single client row for a device in a given org (nil = Aponte-wide).
  defp client_sub(endpoint, org_id) do
    PushSubscription
    |> where(endpoint: ^endpoint)
    |> where(audience: :client)
    |> for_org(org_id)
    |> Repo.one()
  end

  @spec list_subscriptions(audience :: :admin | :client | nil) :: [PushSubscription.t()]
  def list_subscriptions(audience \\ nil) do
    PushSubscription
    |> filter_audience(audience)
    |> Repo.all()
  end

  defp filter_audience(query, nil), do: query
  defp filter_audience(query, audience), do: where(query, audience: ^audience)

  @spec subscription_count() :: non_neg_integer()
  def subscription_count, do: Repo.aggregate(PushSubscription, :count, :id)

  # ── Admin notifications ────────────────────────────────────────────────────

  @spec notify_admin_new_order(Order.t()) :: :ok
  def notify_admin_new_order(%Order{} = order) do
    order = preload_for_notify(order)

    payload = %{
      "t" => "new_order",
      "id" => order.id,
      "n" => first_name(order.customer_name),
      "v" => format_money(order.total_cents),
      "q" => Enum.sum(Enum.map(order.items || [], & &1.quantity)),
      "url" => admin_order_url(order)
    }

    fanout(payload, audience: :admin, urgency: "high", topic: "order-" <> short_id(order.id))
  end

  @spec notify_admin_soldout(TicketType.t()) :: :ok
  def notify_admin_soldout(%TicketType{} = type) do
    payload = %{
      "t" => "soldout",
      "name" => type.name,
      "url" => "/admin"
    }

    fanout(payload, audience: :admin, urgency: "normal", topic: "soldout-" <> short_id(type.id))
  end

  @spec notify_admin_dj_application(%{name: String.t()}, Org.t() | nil) :: :ok
  def notify_admin_dj_application(%{name: name}, org \\ nil) do
    fanout(dj_application_payload(name, org), audience: :admin, urgency: "normal")
  end

  @doc "Push payload for a new DJ application. Pure; the org scopes the admin URL."
  @spec dj_application_payload(String.t() | nil, Org.t() | nil) :: map()
  def dj_application_payload(name, org) do
    %{
      "t" => "dj_application",
      "n" => first_name(name),
      "url" => dj_admin_url(org)
    }
  end

  # Org-aware admin URL; nil org covers ad-hoc callers without one.
  defp dj_admin_url(%Org{slug: slug}), do: "/admin/#{slug}/tocar"
  defp dj_admin_url(nil), do: "/admin"

  # ── Customer notifications ─────────────────────────────────────────────────

  @doc """
  Pushes a status update to the device that placed `order` (if it subscribed
  and opted into `order_status`). No-op when the order has no linked device.
  """
  @spec notify_customer_order_update(Order.t()) :: :ok
  def notify_customer_order_update(%Order{client_endpoint: endpoint, status: status} = order)
      when is_binary(endpoint) do
    order = preload_for_notify(order)

    with %PushSubscription{topics: topics} = sub <- client_sub(endpoint, order.org_id),
         true <- "order_status" in (topics || []) do
      payload = %{
        "t" => "order_status",
        "id" => order.id,
        "s" => to_string(status),
        "url" => order_url(order)
      }

      Task.start(fn ->
        push_one(sub, payload, urgency: "high", topic: "status-" <> short_id(order.id))
      end)
    end

    :ok
  end

  def notify_customer_order_update(_), do: :ok

  @doc """
  Pushes a "your coupon expires tomorrow" notice to the coupon's device, if it
  subscribed and opted into `coupons`. No-op otherwise.
  """
  @spec notify_coupon_expiring(%{client_endpoint: String.t() | nil, code: String.t()}) :: :ok
  def notify_coupon_expiring(%{client_endpoint: endpoint, code: code} = coupon)
      when is_binary(endpoint) do
    with %PushSubscription{topics: topics} = sub <- client_sub(endpoint, Map.get(coupon, :org_id)),
         true <- "coupons" in (topics || []) do
      payload = %{"t" => "coupon_expiring", "code" => code, "url" => "/"}
      Task.start(fn -> push_one(sub, payload, urgency: "normal", topic: "coupon-#{code}") end)
    end

    :ok
  end

  def notify_coupon_expiring(_), do: :ok

  @doc "Anuncia uma edição recém-publicada aos clientes da org opt-in em `editions`."
  @spec announce_edition(Edition.t()) :: :ok
  def announce_edition(%Edition{} = edition) do
    payload = %{
      "t" => "edition",
      "title" => "#{edition.name} anunciada",
      "body" => "#{Clock.format(edition.starts_at, :date)} - #{edition.venue}",
      "url" => "/"
    }

    PushSubscription
    |> where([s], s.audience == :client)
    |> for_org(edition.org_id)
    |> Repo.all()
    |> Enum.filter(&("editions" in (&1.topics || [])))
    |> Enum.each(fn sub -> Task.start(fn -> push_one(sub, payload, urgency: "low") end) end)

    :ok
  end

  # Edition org is always set in practice; nil covers Aponte-wide (org-less) subs.
  defp for_org(query, nil), do: where(query, [s], is_nil(s.org_id))
  defp for_org(query, org_id), do: where(query, [s], s.org_id == ^org_id)

  @doc "Announces a newly-created public coupon to that org's `coupons`-opted clients."
  @spec announce_coupon(%{
          org_id: Ecto.UUID.t() | nil,
          code: String.t(),
          discount_kind: atom(),
          discount_value: integer(),
          expires_at: DateTime.t() | nil
        }) :: :ok
  def announce_coupon(%{
        org_id: org_id,
        code: code,
        discount_kind: kind,
        discount_value: value,
        expires_at: exp
      }) do
    body = "Use #{code} - #{discount_label(kind, value)}#{expiry_suffix(exp)}"

    payload = %{"t" => "coupon", "title" => "Novo cupom", "body" => body, "url" => "/"}

    PushSubscription
    |> where([s], s.audience == :client)
    |> for_org(org_id)
    |> Repo.all()
    |> Enum.filter(&("coupons" in (&1.topics || [])))
    |> Enum.each(fn sub -> Task.start(fn -> push_one(sub, payload, urgency: "low") end) end)

    :ok
  end

  defp discount_label(:percent, value), do: "#{value}% off"
  defp discount_label(:fixed, value), do: "R$ #{format_money(value)} off"

  defp expiry_suffix(nil), do: ""
  defp expiry_suffix(%DateTime{} = exp), do: " até #{Clock.format(exp, :date)}"

  # ── internals ──────────────────────────────────────────────────────────────

  defp fanout(payload, opts) do
    {audience, push_opts} = Keyword.pop!(opts, :audience)

    case list_subscriptions(audience) do
      [] ->
        Logger.debug("[notifications] no #{audience} subscriptions, skipping #{payload["t"]}")
        :ok

      subs ->
        Enum.each(subs, fn sub ->
          Task.start(fn -> push_one(sub, payload, push_opts) end)
        end)

        :ok
    end
  end

  defp push_one(sub, payload, opts) do
    subscription = %WebPush.Subscription{
      endpoint: sub.endpoint,
      p256dh: sub.p256dh,
      auth: sub.auth
    }

    case WebPush.send(subscription, payload, opts) do
      :ok -> :ok
      {:error, :gone} -> unsubscribe(sub.endpoint)
      {:error, _reason} -> :ok
    end
  end

  defp preload_for_notify(%Order{} = order), do: Repo.preload(order, [:items, :org])

  # Org-aware URLs; the bare fallback keeps ad-hoc callers (backfill-ish
  # structs, tests) that never persisted the order working.
  defp order_url(%Order{org: %Org{slug: slug}} = order), do: "/#{slug}/compra/#{order.id}"
  defp order_url(%Order{} = order), do: "/compra/#{order.id}"

  defp admin_order_url(%Order{org: %Org{slug: slug}} = order),
    do: "/admin/#{slug}/pedidos/#{order.id}"

  defp admin_order_url(%Order{} = order), do: "/admin/pedidos/#{order.id}"

  defp first_name(nil), do: ""

  defp first_name(name) do
    name |> String.split(~r/\s+/, parts: 2) |> List.first()
  end

  defp format_money(cents) when is_integer(cents) do
    (cents / 100)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
  end

  defp format_money(_), do: ""

  # Topic must be URL-safe ≤ 32 chars; UUIDs are 36 so we shorten.
  defp short_id(id), do: id |> String.replace("-", "") |> binary_part(0, 16)
end
