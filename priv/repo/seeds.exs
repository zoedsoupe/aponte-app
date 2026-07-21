# Seeds de desenvolvimento: 2 edições com accents e lotes distintos.
# Idempotente: pula edições cujo `number` já existe.
#
#   mix run priv/repo/seeds.exs

import Ecto.Query

alias Aponte.Editions
alias Aponte.Editions.Edition
alias Aponte.Orgs.Org
alias Aponte.Repo

# Orgs foram criadas pela migration 20260719000001 (seed "sesh" lendo PIX_KEY).
org = Repo.get_by!(Org, slug: "sesh")

# Perfil da org: about recuperado do antigo /sobre (git history, pre-vitrine),
# instagram e tema escuro clássico da SESH. Idempotente (update direto).
about = """
A SESH é um rolê experimental pensado pra formar uma comunidade em torno da música eletrônica em todos os seus formatos e estilos.

Nossa proposta é criar um espaço acessível pra quem quer curtir e pros novos DJs que estão buscando lugar pra se lançar.

Tem uma baguncinha no início, com os DJs trocando ideia sobre produção, e depois muita música estranha até as 5h da manhã.
"""

{:ok, org} =
  Aponte.Orgs.update_org(org, %{
    about: String.trim(about),
    instagram: "coletivo.sesh",
    accent_color: "#F07BC0",
    bg_color: "#05070a",
    fg_color: "#f3f3f3"
  })

upsert = fn attrs ->
  number = attrs.number

  if Repo.exists?(from(e in Edition, where: e.number == ^number and e.org_id == ^org.id)) do
    IO.puts("· edição ##{number} já existe — pulando")
    nil
  else
    {:ok, ed} = Editions.create_edition(org, attrs)
    IO.puts("✓ criada edição ##{number}: #{ed.name} (#{ed.accent_color})")
    ed
  end
end

# Edição 1 — rosa (accent padrão), será a publicada/atual.
ed1 =
  upsert.(%{
    number: 1,
    name: "SESH #1",
    starts_at: ~U[2026-06-28 00:00:00Z],
    venue: "OCA ROOTS",
    venue_address: "Campos dos Goytacazes — RJ",
    lineup: "ANTUNIO\nBRED\nE CONVIDADOS",
    status: :draft,
    accent_color: "#F07BC0",
    ticket_types: [
      %{
        name: "Lista Amiga",
        description: "marque 2 amigos no post do Instagram (@coletivo.sesh)",
        price_cents: 1000,
        capacity: 50,
        position: 0,
        is_active: true
      },
      %{name: "Lote 1", price_cents: 1500, capacity: 80, position: 1, is_active: true},
      %{name: "Porta", price_cents: 2000, capacity: 40, position: 2, is_active: true}
    ]
  })

# Edição 2 — ciano neon (accent diferente), fica em draft.
upsert.(%{
  number: 2,
  name: "SESH #2",
  starts_at: ~U[2026-07-26 00:00:00Z],
  venue: "A DEFINIR",
  lineup: "LINEUP EM BREVE",
  status: :draft,
  accent_color: "#16C8D8",
  ticket_types: [
    %{
      name: "Pré-venda",
      description: "primeiro lote, preço amigo — corre que acaba",
      price_cents: 1200,
      capacity: 100,
      position: 0,
      is_active: true
    },
    %{name: "Pista", price_cents: 2500, capacity: 120, position: 1, is_active: false}
  ]
})

# Publica a #1 (vira a edição atual da landing; arquiva qualquer outra publicada).
if ed1, do: {:ok, _} = Editions.publish(ed1)

# ── Merch (catálogo global da loja) ───────────────────────────────────────────
# Idempotente: pula itens cujo `name` já existe.
alias Aponte.Merch
alias Aponte.Merch.Item

merch_upsert = fn attrs ->
  if Repo.exists?(from(m in Item, where: m.name == ^attrs.name)) do
    IO.puts("· merch “#{attrs.name}” já existe — pulando")
  else
    {:ok, item} = Merch.create_item(Map.put(attrs, :org_id, org.id))
    IO.puts("✓ criado merch: #{item.name} (#{item.available}/#{item.stock})")
  end
end

[
  %{
    name: "Bolsinha",
    description: "lona, serigrafia da casa",
    price_cents: 3000,
    stock: 25,
    position: 0
  },
  %{
    name: "Adesivo",
    description: "vinil holográfico, 8cm",
    price_cents: 500,
    stock: 200,
    position: 1
  },
  %{
    name: "Poster A3",
    description: "fosco 250g, edição numerada",
    price_cents: 2500,
    stock: 40,
    position: 2
  },
  %{
    name: "Camiseta",
    description: "preta, estampa SESH nas costas",
    price_cents: 6000,
    stock: 30,
    position: 3,
    is_active: false
  },
  # Balcão (POS da festa). Água/cerveja rastreiam estoque; cigarro/pirulito não.
  %{name: "Água", price_cents: 500, kind: :counter, track_stock: true, stock: 60, position: 0},
  %{
    name: "Cerveja",
    price_cents: 1000,
    kind: :counter,
    track_stock: true,
    stock: 120,
    position: 1
  },
  %{name: "Cigarro", price_cents: 200, kind: :counter, track_stock: false, position: 2},
  %{name: "Pirulito", price_cents: 300, kind: :counter, track_stock: false, position: 3}
]
|> Enum.each(merch_upsert)

IO.puts("seeds ok")
