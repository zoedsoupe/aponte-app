export function bindFormGate(form) {
  if (!form) return;

  const submit = form.querySelector("button[type=submit]");
  if (!submit) return;

  // Comprar tickets name their quantities items[...]; loja merch uses
  // merch[...] (the comprar form can also carry merch). Both count as cart.
  const qtyInputs = form.querySelectorAll(
    'input[name^="items["], input[name^="merch["]',
  );

  const instagram = form.querySelector('[name="order[customer_instagram]"]');
  const phone = form.querySelector('[name="order[customer_phone]"]');
  const hint = form.querySelector("[data-gate-hint]");

  const hasItems = () => {
    for (const el of qtyInputs) {
      if (Number(el.value) > 0) return true;
    }
    return false;
  };

  // Buyer identity is "instagram OR phone": at least one non-empty. Forms
  // without identity fields (defensive) are not gated on it.
  const hasIdentity = () => {
    if (!instagram && !phone) return true;
    return Boolean(instagram?.value.trim() || phone?.value.trim());
  };

  const update = () => {
    const items = hasItems();
    const identity = hasIdentity();
    const valid = form.checkValidity() && items && identity;
    submit.disabled = !valid;
    submit.classList.toggle("is-disabled", !valid);

    if (hint) {
      // Name the first blocker, cleared when the form is submittable.
      const msg = !items
        ? "escolha pelo menos 1 ingresso"
        : !identity
          ? "informe seu instagram ou telefone"
          : "";
      hint.textContent = msg;
      hint.hidden = msg === "";
    }
  };

  form.addEventListener("input", update);
  form.addEventListener("change", update);
  update();
}
