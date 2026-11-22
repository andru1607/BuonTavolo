/* GoodDiner: user-safe messages for Supabase Auth failures. No secrets or debug logs. */
(function (scope) {
  'use strict';
  function explain(error) {
    const info = (String(error?.code || '') + ' ' + String(error?.message || '')).toLowerCase();
    if (/gooddiner_invite|invitation.*(invalid|expired|used)/.test(info))
      return 'Il codice di invito non è valido, è scaduto o è già stato usato. Richiedine uno nuovo.';
    if (/gooddiner_registration_closed|signup.*disabled|signups? not allowed/.test(info))
      return 'Le nuove iscrizioni sono temporaneamente sospese. Riprova più tardi.';
    if (/email_not_confirmed|email.*not confirmed|email.*not verified/.test(info))
      return 'Devi confermare il tuo indirizzo email prima di accedere. Controlla anche la posta indesiderata.';
    if (/invalid_credentials|invalid login credentials|invalid_grant/.test(info))
      return 'Email o password non corretti. Verifica i dati oppure recupera la password.';
    if (/user_already_exists|already registered|already exists/.test(info))
      return 'Questo indirizzo potrebbe essere già registrato. Prova ad accedere o a recuperare la password.';
    if (/email_address_invalid|invalid email|email.*invalid/.test(info))
      return 'Controlla il formato dell’indirizzo email.';
    if (/weak_password|password.*(short|weak|at least)/.test(info))
      return 'Scegli una password più sicura, di almeno 10 caratteri.';
    if (/rate_limit|rate limit|too many requests|429|over_email_send/.test(info))
      return 'Hai effettuato troppi tentativi. Attendi qualche minuto prima di riprovare.';
    if (/captcha|challenge.*(invalid|failed)/.test(info))
      return 'La verifica anti-bot non è riuscita. Ripeti il controllo e riprova.';
    if (/otp_expired|token expired|expired.*token/.test(info))
      return 'Il collegamento è scaduto. Richiedi una nuova email di conferma.';
    return 'Non è stato possibile completare l’operazione. Riprova più tardi.';
  }
  function emailConfirmed(user) {
    return Boolean(user && !user.is_anonymous && typeof user.email === 'string'
      && user.email.includes('@') && user.email_confirmed_at);
  }
  const api = Object.freeze({explain, emailConfirmed});
  scope.GoodDinerAuthUX = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
