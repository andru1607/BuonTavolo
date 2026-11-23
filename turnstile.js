/* GoodDiner: Cloudflare Turnstile browser adapter.
   Publishable SITE key only. Supabase Auth must validate tokens server-side. */
(() => {
  'use strict';
  const config = window.GOODDINER_PUBLIC_CONFIG || {};
  const siteKey = String(config.turnstileSiteKey || '').trim();
  const scriptId = 'gd-turnstile-sdk';
  const tokenMaxAgeMs = 4 * 60 * 1000; // Cloudflare tokens expire after 5 minutes.
  let loading = false;
  const widgets = new Map();       // slot => widget id
  const verifiedAt = new WeakMap(); // form => token issuance timestamp
  const enabled = () => Boolean(siteKey);
  const slotFor = form => form?.querySelector?.('[data-gd-captcha]');
  const inputFor = form => form?.querySelector?.('[name="captchaToken"]');
  const statusFor = form => form?.querySelector?.('[data-gd-captcha-status]');
  const message = (form, text) => {
    const status = statusFor(form);
    if (status) status.textContent = text;
  };
  const clearToken = form => {
    const input = inputFor(form);
    if (input) input.value = '';
    if (form) verifiedAt.delete(form);
  };

  function cleanup() {
    for (const widgetId of widgets.values()) {
      try { window.turnstile?.remove(widgetId); } catch {}
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
        document.querySelectorAll('[data-gd-captcha]').forEach(slot => {
          message(slot.closest('form'), 'La verifica anti-bot non si carica. Controlla la rete e riapri il modulo.');
        });
      };
      document.head.appendChild(script);
      return;
    }
    slots.forEach(slot => {
      if (widgets.has(slot)) return;
      const form = slot.closest('form');
      const input = inputFor(form);
      if (!input || !form) return;
      try {
        const id = window.turnstile.render(slot, {
          sitekey: siteKey,
          action: String(slot.dataset.gdCaptcha || 'signup'),
          callback(token) {
            clearToken(form);
            if (token) {
              input.value = String(token);
              verifiedAt.set(form, Date.now());
              message(form, 'Verifica completata. Puoi proseguire.');
            } else {
              message(form, 'La verifica non è riuscita. Riprova.');
            }
          },
          'expired-callback'() {
            clearToken(form);
            message(form, 'La verifica è scaduta. Completa nuovamente il controllo.');
          },
          'error-callback'() {
            clearToken(form);
            message(form, 'La verifica anti-bot non è riuscita. Riprova o riapri il modulo.');
          }
        });
        if (id !== null && id !== undefined) widgets.set(slot, id);
        else message(form, 'Verifica anti-bot non disponibile. Riapri il modulo.');
      } catch {
        clearToken(form);
        message(form, 'Verifica anti-bot non disponibile. Riapri il modulo.');
      }
    });
  }

  function token(form, required = false) {
    if (!siteKey) {
      if (required) throw Error('Verifica anti-bot non configurata. Non è possibile proseguire.');
      return null;
    }
    const slot = slotFor(form);
    if (!slot || !widgets.has(slot)) {
      message(form, 'La verifica si sta caricando. Attendi o riapri il modulo.');
      throw Error('Verifica anti-bot non pronta. Attendi qualche istante.');
    }
    const value = String(inputFor(form)?.value || '');
    const verified = verifiedAt.get(form);
    if (!value || !Number.isFinite(verified)) {
      message(form, 'Completa la verifica anti-bot prima di proseguire.');
      throw Error('Completa la verifica anti-bot prima di proseguire.');
    }
    if (Date.now() - verified >= tokenMaxAgeMs) {
      resetFor(form);
      message(form, 'La verifica è scaduta. Completala di nuovo.');
      throw Error('La verifica anti-bot è scaduta. Completala di nuovo.');
    }
    return value;
  }

  function resetFor(form) {
    if (!form) return;
    clearToken(form);
    const id = widgets.get(slotFor(form));
    if (id !== undefined) {
      try { window.turnstile?.reset(id); } catch {}
    }
  }

  window.GoodDinerCaptcha = Object.freeze({ enabled, mount, cleanup, token, resetFor });
})();
