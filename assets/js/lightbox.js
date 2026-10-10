// In-app gallery lightbox. Tapping a thumb used to navigate to the raw
// /uploads/*.webp, which ejected the user from the PWA (no tab bar, no way
// back on iOS). This opens the full image in an overlay instead; the anchor's
// href is kept for long-press save / open-in-new-tab.
export function bindGalleryLightbox() {
  const gallery = document.querySelector("[data-gallery]");
  if (!gallery) return;

  const links = Array.from(gallery.querySelectorAll("a[data-lightbox]"));
  if (!links.length) return;

  let index = 0;

  const overlay = document.createElement("div");
  overlay.className = "lightbox";
  overlay.hidden = true;
  overlay.setAttribute("role", "dialog");
  overlay.setAttribute("aria-modal", "true");
  overlay.innerHTML = `
    <button type="button" class="lightbox-close" aria-label="fechar">×</button>
    <img class="lightbox-img" alt="" />
    <button type="button" class="lightbox-nav lightbox-prev" aria-label="foto anterior">‹</button>
    <button type="button" class="lightbox-nav lightbox-next" aria-label="próxima foto">›</button>
  `;
  document.body.appendChild(overlay);

  const img = overlay.querySelector(".lightbox-img");
  const prev = overlay.querySelector(".lightbox-prev");
  const next = overlay.querySelector(".lightbox-next");

  function show(i) {
    index = (i + links.length) % links.length;
    img.src = links[index].getAttribute("href");
    overlay.hidden = false;
  }

  function hide() {
    overlay.hidden = true;
    img.removeAttribute("src");
  }

  links.forEach((a, i) => {
    a.addEventListener("click", (e) => {
      e.preventDefault();
      show(i);
    });
  });

  overlay.querySelector(".lightbox-close").addEventListener("click", hide);
  prev.addEventListener("click", (e) => {
    e.stopPropagation();
    show(index - 1);
  });
  next.addEventListener("click", (e) => {
    e.stopPropagation();
    show(index + 1);
  });
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) hide();
  });

  // Show nav only when there is more than one photo.
  if (links.length < 2) {
    prev.hidden = true;
    next.hidden = true;
  }

  document.addEventListener("keydown", (e) => {
    if (overlay.hidden) return;
    if (e.key === "Escape") hide();
    else if (e.key === "ArrowLeft") show(index - 1);
    else if (e.key === "ArrowRight") show(index + 1);
  });
}
