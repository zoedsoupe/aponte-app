// The floating CTA ducks away on scroll down and returns on scroll up.
// Passive listener, class toggles only (no inline styles) so nothing fights
// LiveView morphing if these pages ever become LiveViews. The element is
// re-queried per event so a late-rendered CTA (e.g. after a patch) is found.

let bound = false;
let lastY = 0;

export function bindScrollFx() {
  if (bound) return;
  if (!document.querySelector("[data-floating-cta]")) return;
  bound = true;

  window.addEventListener(
    "scroll",
    () => {
      const y = window.scrollY;
      const goingDown = y > lastY && y > 64;

      const cta = document.querySelector("[data-floating-cta]");
      if (cta) cta.classList.toggle("is-hidden", goingDown);

      lastY = y;
    },
    { passive: true },
  );
}
