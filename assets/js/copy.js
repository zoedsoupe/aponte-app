export function bindCopyButtons(root = document) {
  root.querySelectorAll("[data-copy-target]").forEach((btn) => {
    if (btn.dataset.bound) return;
    btn.dataset.bound = "1";

    btn.addEventListener("click", async () => {
      const target = document.querySelector(btn.dataset.copyTarget);
      if (!target) return;
      try {
        await navigator.clipboard.writeText(target.textContent.trim());
        const original = btn.textContent;
        btn.textContent = "copiado";
        setTimeout(() => (btn.textContent = original), 1500);
      } catch {
        // Clipboard API denied (insecure context, permission): select the
        // text so the buyer can copy it by hand, and say so on the button.
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        btn.textContent = "copia manualmente acima";
      }
    });
  });
}
