// Client-side order history. No backend: order ids are capability URLs
// (UUIDv4 at /compra/:id, which already renders status + PIX). We just
// remember the ids THIS device created so the customer can return to them
// without bookmarking. Mirrors the localStorage pattern in storage.js.

const KEY = "aponte.orders.v1";
const MAX = 30;

function read() {
  try {
    const v = JSON.parse(localStorage.getItem(KEY));
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

function write(list) {
  localStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX)));
}

// Record the order rendered on the current /compra/:id page. Idempotent —
// revisiting an order moves it to the top instead of duplicating.
export function bindOrderRecord() {
  const el = document.querySelector("[data-order-record]");
  const id = el?.dataset.id;
  if (!id) return;

  const entry = { id, label: el.dataset.label || id, slug: el.dataset.orgSlug };
  const list = read().filter((o) => o.id !== id);
  list.unshift(entry);
  write(list);
}

// Pending order page: poll the same URL while the tab is visible and reload as
// soon as the producer confirms. Replaces a blind <meta refresh> that reset
// scroll while the buyer copied the PIX code and did nothing in the background.
export function watchPendingOrder() {
  const marker = document.querySelector("[data-order-watch]");
  if (!marker) return;

  const url = marker.dataset.url || location.href;
  const current = marker.dataset.orderStatus || "";
  const note = document.querySelector("[data-order-updating]");
  let timer = null;
  let checking = false;

  async function check() {
    if (document.hidden || checking) return;
    checking = true;
    if (note) note.hidden = false;

    try {
      const res = await fetch(url, { credentials: "same-origin" });
      if (res.ok) {
        const doc = new DOMParser().parseFromString(await res.text(), "text/html");
        const next = doc.querySelector("[data-order-watch]");
        if (next && (next.dataset.orderStatus || "") !== current) {
          location.reload();
          return;
        }
      }
    } catch {
      // offline or flaky venue data: keep the last state, retry next tick
    } finally {
      checking = false;
      if (note) note.hidden = true;
    }
  }

  function start() {
    if (!timer) timer = setInterval(check, 12000);
  }

  function stop() {
    if (timer) clearInterval(timer);
    timer = null;
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      stop();
    } else {
      start();
      check();
    }
  });

  if (!document.hidden) {
    start();
    check();
  }
}

// Static inline chevron (same mark as the server-rendered inset rows).
const CHEV_SVG =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" class="inset-chev" aria-hidden="true"><path d="m9 5 7 7-7 7" /></svg>';

// Populate [data-order-history] with links to each saved order, newest first.
// Links are org-scoped: the container carries data-org-slug (rendered by the
// history page) and orders live under /<slug>/compra/<id>. Shows an empty
// state when this device has no history.
export function renderOrderHistory() {
  const root = document.querySelector("[data-order-history]");
  if (!root) return;

  const slug = root.dataset.orgSlug;
  // Entries carry the org slug they were created under. Slugless legacy
  // entries are ambiguous (they 404 under the wrong org), so they stay in
  // storage but out of the list; visiting the order's real link re-records
  // it with the slug.
  const list = read().filter((o) => o.slug === slug);
  root.replaceChildren();

  if (!list.length) {
    const p = document.createElement("p");
    p.className = "text-xs text-dim";
    p.textContent = "Nenhum pedido neste aparelho ainda.";
    root.appendChild(p);
    return;
  }

  const ul = document.createElement("ul");
  ul.className = "inset-list";

  for (const o of list) {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = orderUrl(o.slug || slug, o.id);
    a.className = "inset-row";

    const label = document.createElement("span");
    label.className = "text-base text-mono";
    label.textContent = o.label || o.id;

    a.appendChild(label);
    a.insertAdjacentHTML("beforeend", CHEV_SVG);
    li.appendChild(a);
    ul.appendChild(li);
  }

  root.appendChild(ul);
}

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

// Org-scoped order URL. Without a slug (defensive) falls back to the legacy
// bare path.
function orderUrl(slug, id) {
  const path = `/compra/${encodeURIComponent(id)}`;
  return slug ? `/${slug}${path}` : path;
}

// Accepts both org-scoped (/<slug>/compra/<uuid>) and legacy bare
// (/compra/<uuid>) links buyers saved, with or without scheme+host.
// Group 1 = optional org slug, group 2 = order id.
const COMPRA_LINK = new RegExp(
  `(?:/([a-z0-9][a-z0-9-]*))?/compra/(${UUID.source})`,
  "i",
);

// Import an order this device never visited (e.g. a backfilled order whose
// link arrived by DM). On iOS the standalone PWA has its own localStorage,
// isolated from Safari — an external link can't reach it. The escape hatch:
// paste the /compra link HERE, inside the PWA, and we navigate to it in-scope
// so the show page's bindOrderRecord() writes to the PWA's own store.
export function bindOrderImport() {
  const form = document.querySelector("[data-order-import]");
  if (!form) return;

  const input = form.querySelector("input");

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const m = input.value.match(COMPRA_LINK);
    const id = m?.[2];
    if (!id) {
      input.setCustomValidity("link inválido - cole o /compra/... que você recebeu.");
      input.reportValidity();
      return;
    }
    // In-scope navigation: stays in the PWA context, so the order is recorded
    // in this store on arrival. The link's own org wins — rewriting it to the
    // current org would 404 (orders are org-scoped).
    location.assign(orderUrl(m[1] || form.dataset.orgSlug, id));
  });

  input.addEventListener("input", () => input.setCustomValidity(""));
}
