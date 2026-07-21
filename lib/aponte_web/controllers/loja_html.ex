defmodule AponteWeb.LojaHTML do
  @moduledoc false
  use AponteWeb, :html

  alias Aponte.Merch

  embed_templates "loja_html/*"

  # Subtler than the ticket lot_row: image, name, price, description, stepper.
  attr :items, :list, required: true
  attr :qtys, :map, required: true

  def store_card(assigns) do
    ~H"""
    <li :for={item <- @items} class="store-card">
      <a
        :if={item.image_path}
        href={Merch.image_url(item.image_path)}
        target="_blank"
        rel="noopener"
        class="store-card-photo"
      >
        <img src={Merch.image_url(item.image_path)} alt={item.name} loading="lazy" />
      </a>
      <div :if={!item.image_path} class="store-card-photo store-card-photo--empty" aria-hidden="true">
        {String.first(item.name)}
      </div>
      <div class="store-card-body stack-2">
        <div class="row space-between align-baseline">
          <span class="text-base">{item.name}</span>
          <span class="text-sm text-dim text-mono">{money(item.price_cents)}</span>
        </div>
        <p :if={item.description not in [nil, ""]} class="text-xs text-dim">{item.description}</p>
        <.qty_stepper
          name={"merch[#{item.id}]"}
          value={Map.get(@qtys, item.id) || Map.get(@qtys, to_string(item.id)) || 0}
          max={item.available}
          label={item.name}
        />
      </div>
    </li>
    """
  end
end
