const boundRoots = new WeakSet();

export function bindCopyButtons(root = document) {
  if (boundRoots.has(root)) return;
  boundRoots.add(root);

  root.addEventListener("click", async (event) => {
    const btn = event.target.closest("[data-copy-target], [data-copy-text]");
    if (!btn || !root.contains(btn)) return;

    const target = btn.dataset.copyTarget
      ? document.querySelector(btn.dataset.copyTarget)
      : null;
    const text = btn.dataset.copyText || target?.textContent.trim();
    if (!text) return;

    const original = btn.textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
      btn.textContent = "Copiado";
      setTimeout(() => (btn.textContent = original), 1500);
    } catch {
      if (target) {
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        btn.textContent = "Copie manualmente acima";
      } else {
        btn.textContent = "Não foi possível copiar";
        setTimeout(() => (btn.textContent = original), 1500);
      }
    }
  });
}
