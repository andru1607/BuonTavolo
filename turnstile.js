/* GoodDiner: browser-only Cloudflare Turnstile adapter. PUBLIC site key only. */
(() => {
  'use strict';
  const config = window.GOODDINER_PUBLIC_CONFIG || {};
  const siteKey = String(config.turnstileSiteKey || '').trim();
  const scriptId = 'gd-turnstile-sdk';
  let loading = false;
  const widgets = new Map();
  const enabled = () => Boolean(siteKey);
  const hasWidget = form => Boolean(form?.querySelector?.('[data-gd-captcha]'));
  const inputFor = form => form?.querySelector?.('[name="captchaToken"]');

  function cleanup() {
    for (const id of widgets.values()) {
      try { window.turnstile?.remove(id); } catch {}
    }
    widgets.clear();
  }

  function mount() {
    if (!siteKey) return;
    const slots = document.querySelectorAll('[data-gd-captcha]');
    if (!slots?.length) return;
    if (!window.turnstile) {
      if (loading || document.getElementById(scriptId)) return;
      loading = true;
      const script = document.createElement('script');
      script.id = scriptId;
      script.async = true;
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
      script.onload = () => { loading = false; mount(); };
      script.onerror = () => {
        loading = false;
        script.remove();
        slots.forEach(slot => {
          slot.textContent = 'Verifica anti-bot non disponibile. Controlla la connessione.';
        });
      };
      document.head.appendChild(script);
      return;
    }
    slots.forEach(slot => {
      if (widgets.has(slot)) return;
      const form = slot.closest('form');
      const input = inputFor(form);
      if (!input) return;
      const id = window.turnstile.render(slot, {
        sitekey: siteKey,
        action: String(slot.dataset.gdCaptcha || 'login'),
        callback(token) { input.value = String(token || ''); },
        'expired-callback'() { input.value = ''; },
        'error-callback'() { input.value = ''; }
      });
      widgets.set(slot, id);
    });
  }

  function token(form, required = false) {
    if (!siteKey) {
      if (required) throw Error('Verifica anti-bot non configurata: registrazioni chiuse.');
      return null;
    }
    if (!hasWidget(form)) throw Error('Verifica anti-bot mancante. Riapri il modulo.');
    const token = String(inputFor(form)?.value || '');
    if (!token) throw Error('Completa la verifica anti-bot prima di proseguire.');
    return token;
  }

  function resetFor(form) {
    const field = inputFor(form);
    if (field) field.value = '';
    const slot = form?.querySelector?.('[data-gd-captcha]');
    const id = widgets.get(slot);
    if (id !== undefined) {
      try { window.turnstile?.reset(id); } catch {}
    }
  }

  window.GoodDinerCaptcha = Object.freeze({ enabled, mount, cleanup, token, resetFor });
})();
