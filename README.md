# Aponte

App da Aponte Produtora: agregador de eventos de Campos, onde cada evento tem
página própria com identidade própria, venda de ingresso com PIX direto na
chave do produtor e validação de QR na porta.

Este repo nasceu como `sesh_lab` (o site do coletivo SESH) e está virando o
Aponte. O escopo aprovado da transição está em `SPEC_APONTE.md` e a spec
técnica do refactor em `SPEC_APONTE_V1.md`.

## Por que existe

Produtor pequeno não precisa de Sympla cobrando 10% de taxa, nem de gateway de
pagamento, nem de planilha no grupo pra saber quem pagou. Precisa de:

- uma página por evento que pareça o flyer da edição e carregue rápido no
  celular na fila da porta;
- vender ingresso recebendo PIX direto na chave do produtor (confirmação
  manual, sem API de pagamento);
- emitir ingresso ao portador com QR pra validar na entrada, com código curto
  digitado na mão como fallback;
- vitrine do rolê: fotos, sobre, links, e um canal pro público pedir aviso de
  nova edição.

O dinheiro do ingresso nunca passa pela Aponte. A Aponte cobra uma taxa flat
pela ferramenta, não pela venda.

Tudo roda numa VM única e barata. Sem dependência externa que possa cair (ou
cobrar) no meio do evento.

## Domínio

orgs (eventos/coletivos) -> edições -> lotes -> pedidos -> ingressos emitidos
-> validação na porta. Cada org tem slug próprio (`/sesh`, `/arena`), tema por
accent color, galeria de fotos e chave pix própria.

Copy em pt-BR, sem nomes pessoais no site, sem emoji.

## Stack

- Phoenix 1.8 + LiveView 1.1
- SQLite via `ecto_sqlite3` (um arquivo, um volume, fim)
- esbuild puro pra JS e CSS: sem Tailwind, sem Node em runtime, sem CDN
- PWA com service worker manual, manifest e ícones
- PIX EMV BR Code gerado na unha (`lib/sesh_lab/payments/pix.ex`)
- Web Push VAPID manual, RFC completo (`lib/sesh_lab/notifications/web_push/`)
- Imagens da vitrine processadas com libvips (pacote `image`)
- Bandit como servidor

## Dev local

Requer Elixir 1.19, OTP 28 e SQLite.

```sh
source .env       # ADMIN_USER, ADMIN_PASS, PIX_KEY (valores de dev ficam no repo local)
mix setup
mix phx.server
```

- Público: http://localhost:4000
- Admin: http://localhost:4000/admin (basic auth via `.env`)

## Deploy

Fly.io, máquina única com volume pra SQLite e uploads (`fly.toml`). Migrações
rodam no boot via `Ecto.Migrator`. Em dia de evento, sobe
`min_machines_running = 1`: cold start no meio da fila da porta não rola.
