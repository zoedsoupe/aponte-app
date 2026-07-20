# Aponte: escopo do produto

Status: aprovado (2026-07-19). Este doc define o que se constrói, em que ordem,
e o que não se constrói. A spec técnica do refactor v1 fica em
`SPEC_APONTE_V1.md`.

## O que é

App da Aponte Produtora: agregador de eventos onde cada evento tem página
própria com identidade própria, venda de ingresso com pix direto na chave do
produtor (sem taxa sobre a venda, sem gateway) e vitrine do rolê (fotos, sobre,
links). Começa como casa dos eventos da própria Aponte (SESH, A Arena) e cresce
pra agregar os rolês de Campos.

Posicionamento: o dinheiro do ingresso nunca passa pela Aponte. A Aponte cobra
pela ferramenta, não pela venda. Esse é o argumento contra Sympla e Shotgun.

## V1: sesh_lab vira aponte (multi-org, operado só pela Aponte)

Refactor in-place: mesmo deploy Fly, mesmo banco SQLite, sem migração externa
de dados.

### Infra / multi-org

- Namespace `SeshLab` -> `Aponte` (mesmo app Fly, mesmo volume).
- Tabela `orgs`: slug, name, about, accent_color, logo_path, instagram,
  pix_key, status, tier (:free/:paid, default free), storage_quota_bytes.
  Backfill: org `sesh` com os dados atuais.
- `org_id` em toda tabela tenant: editions direto; orders, tickets e
  push_subscriptions desnormalizado (nullable em push = avisos Aponte-wide).
- Chave pix sai de env/settings para `orgs.pix_key`. Orders seguem com snapshot
  da chave (já existe).
- Toda query org-scoped. Admin segue basic-auth único, isolado num plug
  (preparado pra trocar por session auth no v2).

### Público

- Rotas `/:org_slug/...` pra tudo que hoje é global (comprar, loja,
  meus-ingressos etc). Plug carrega a org pelo slug; 404 em slug desconhecido
  ou reservado.
- `/` = home Aponte: orgs + edição atual ou próxima de cada. `/sobre` = sobre
  a produtora.
- Tema por org: o accent CSS var sai de "edição publicada global" para "edição
  publicada desta org".
- Paleta Aponte (default plataforma, extraída do logo aquarela 2026-07-20):
  bg `#FEF8DA`, ink `#49422F`, accent `#BF7262` (terracota). Tabela completa
  em `SPEC_APONTE_V1.md` §2.1. Org `sesh` mantém `#F07BC0`.

### Identidade do comprador (sem contas)

- Novo campo `customer_phone` (WhatsApp); `customer_instagram` vira opcional;
  changeset exige um dos dois.
- Meus-ingressos: lookup por telefone + código da order (rate-limited, mostra
  só iniciais). Lookup só por telefone não lista orders (vazamento).

### Vitrine (página da org)

- Galeria por org: upload, listar, deletar, reordenar. Cap de 5MB por imagem.
  Processamento com libvips (pacote `image`): variante web ~1600px webp + thumb
  ~400px webp.
- Arquivos em disco no volume (`/data/uploads/:org_id/`), nomes content-hashed,
  controller com cache longo. Sem blob no SQLite, sem S3.
- Seção sobre: texto `about` + links sociais (label + url).
- Quota de storage checada no upload (soft: avisa, não bloqueia).

### Edições

- `ends_at` nullable. Prepara o terreno pra multi-dia sem construir nada de
  festival.

### Cutover

- Domínio próprio (a comprar; candidato: aponte.live). sesh-lab.fly.dev faz 301
  por uma janela curta e morre. Lista de push morre com a origem (aceito;
  Instagram segura a comunicação).
- Mantém tudo que o sesh_lab já faz, org-scoped: edições, lotes, orders, pix
  EMV, scanner QR, cupons, merch, balcão, "quero tocar", push.

## V2: multi-tenant real (produtores externos)

- Contas de produtor + `org_memberships`; session auth substitui o plug
  basic-auth.
- Onboarding: a Aponte convida via magic link + setup da conta. Invite-only,
  sem signup aberto.
- Monetização: taxa flat por edição (~R$39-49). Publicar edição com ingresso
  pago exige tier pago (paywall no publish). Fatura pix manual, sem gateway.
  Linha do tier: dinheiro-pelo-app (vendeu ingresso pago no app = pago), não
  tamanho do rolê.
- Discovery: home vira listagem dos rolês da cidade. Lista cronológica com
  filtro por semana ("rolês da semana") + categorias (festa, expo etc).
- Mais customização da página do produtor: a definir com o produtor #1.
  Restrição registrada: customização aberta demais fica difícil de gerenciar,
  então o viés é mais alavancas fixas (cor de fundo, fonte entre presets,
  seções opcionais), nunca formato livre nem CSS custom.
- Hard quota enforcement (v1 é soft).

## Deferidos com trigger (não é v2; construir só se o trigger acontecer)

- Tabela `check_ins` (check-in multi-dia de festival). Trigger: um festival
  fechar de verdade.
- Theme engine além das alavancas fixas. Trigger: identidade de uma org não
  caber nas alavancas existentes.
- Contas de comprador. Trigger: transferência ou revenda de ingresso virar
  problema.

## Mortos (não construir)

- Subdomínios ou domínios custom por evento.
- Taxa percentual sobre vendas.
- POS ou sistema de vendas pra barraquinhas de terceiros. Cada barraquinha roda
  seu próprio pix e aparece na página do evento como conteúdo de vitrine.
- Merch global da marca Aponte.
- Gateway de pagamento ou cobrança recorrente automatizada.
- OTP ou verificação por SMS/WhatsApp.
- Signup aberto de produtores.
