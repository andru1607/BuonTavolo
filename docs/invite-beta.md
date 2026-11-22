# GoodDiner · Registrazioni pilota su invito

**Scope esclusivo:** `andru1607/BuonTavolo`, Supabase `ixczkhmvbjszgmlqznlk`. Ultima revisione 22/11/2026.

## Cosa è attivo e cosa no

La versione pilota permette di **creare veri account con email/password soltanto con un codice d'invito monouso**. Non è una registrazione pubblica, non è un lancio commerciale e non serve a raccogliere dati di ospiti reali non informati.

- Un codice è una stringa esadecimale di 32 caratteri, con almeno 122 bit di entropia proveniente da UUIDv4; una sola attivazione per codice.
- L'invito è memorizzato soltanto come hash SHA-256 in `gd_private.signup_invites`. Scade entro 7 giorni e viene segnato come consumato atomicamente dentro l'inserimento Auth. Lo stesso invito non può generare un secondo account.
- Il campo `gd_invite` viene cancellato da `auth.users.raw_user_meta_data` nel trigger BEFORE INSERT. Nessun segreto invito in `profiles` o nei dati pubblici.
- Due tipi: `customer` e `merchant`. Il tipo non concede alcun privilegio; un ristoratore deve **comunque presentare una domanda** e attendere una vera verifica dell'attività prima di scansionare DinerPass. Non è possibile registrarsi come anonimo nel pilota.
- L'app mostra un campo invito, richiede email/password e spiega che i voti sulle persone e i premi restano chiusi.
- Le iscrizioni senza invito, con token già usato/scaduto o di tipo diverso sono rifiutate nel database, anche se qualcuno chiama direttamente le API Auth.
- Il login e recupero degli account già esistenti non richiedono invito. Non memorizzare password/codici in commenti pubblici di GitHub.
- **Cloudflare Turnstile non è configurato**, quindi il modulo email del pilota usa il codice monouso come controllo di ammissione; nessuna iscrizione generale senza anti-bot attivo.

## Come creare inviti da iPhone

Il titolare autorizzato apre [Supabase SQL Editor GoodDiner](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/sql) e, dopo aver identificato il volontario e ottenuto il suo consenso a partecipare al test, esegue:

```sql
-- Risultato: codice segreto monouso da inviare direttamente al tester.
select gd_private.create_signup_invite('customer','operatore-gooddiner',48);
-- Per un candidato ristoratore, solo se davvero richiesto:
select gd_private.create_signup_invite('merchant','operatore-gooddiner',48);
```

L'invito è usabile sulla pagina GoodDiner distribuita tramite HTTPS solo se `registrationEnabled:true` e `registrationMode:'invite'`. I volontari devono inserire un'email vera, verificare il messaggio ricevuto ed effettuare login. Se l'email non arriva, controllare prima provider, SMTP e limiti del progetto; **non simulare un'email verificata aggiornando manualmente la riga `auth.users`**.

Per verificare lo stato senza leggere o diffondere codici:

```sql
select purpose, count(*) filter(where used_at is null and expires_at>now()) as available,
       count(*) filter(where used_at is not null) as consumed
from gd_private.signup_invites group by purpose;
select is_open,invite_only_enabled,changed_by,reason from gd_private.registration_gate;
```

## Attivazione controllata lato server

**Non attivare `is_open=true`**: quello aprirebbe un percorso senza invito. Nel pilota l'unico interruttore abilitato è `invite_only_enabled`, mantenendo `is_open=false`. La modifica viene registrata nell'audit del gate.

```sql
update gd_private.registration_gate
set invite_only_enabled=true, is_open=false,updated_at=now(),
    changed_by='operatore-gooddiner',
    reason='Pilota solo con inviti monouso; signup pubblico chiuso fino a SMTP, CAPTCHA, privacy e collaudo'
where singleton=true;
```

Per sospendere immediatamente tutte le nuove iscrizioni:

```sql
update gd_private.registration_gate
set invite_only_enabled=false, is_open=false,updated_at=now(),
    changed_by='operatore-gooddiner',
    reason='Sospensione preventiva delle nuove iscrizioni pilota'
where singleton=true;
```

La sospensione non interrompe l'accesso di utenti già esistenti.

## Condizioni ancora da verificare

1. **Supabase Auth:** le impostazioni email, URL di redirect e conferma non sono accessibili con gli strumenti di gestione database. Da iPhone aprire [Providers](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/providers), [URL Configuration](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/url-configuration), [Email Templates](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/templates) e impostare il dominio di produzione identificato davvero. Conferma email e recupero vanno testati con recapiti posseduti dai volontari.
2. **Protezione generale:** prima di togliere la richiesta di invito installare Cloudflare Turnstile **sul provider Supabase Auth**, configurando site key pubblica nel client e secret nel dashboard di Auth, e verificare un tentativo HTTP senza token. L'invito non sostituisce il CAPTCHA per un lancio aperto.
3. **Privacy:** definire il titolare e recapito privacy, informativa e base giuridica dei dati del pilota, eventuali responsabili e tempi di conservazione. Non usare nomi o dati reali di clienti casuali nei test.
4. **Dispositivi:** testare due email, un cliente e un ristoratore non approvato, account duplicato, invito sbagliato, email/recupero e impossibilità di usare l'area ristoratore senza autorizzazione. I test SQL non sostituiscono l'uso iPhone Safari.
5. **URL pubblico:** i check Vercel GitHub risultano positivi sul precedente commit, ma manca un dominio canonico HTTPS verificato e il test smoke `GOODDINER_BASE_URL`.

## Rilascio pubblico futuro

Per poter attivare **iscrizioni senza invito** servono prima email/SMTP, anti-bot in Auth, privacy/termini approvati, URL e dispositivi collaudati. Solo dopo, in due passaggi controllati:
1. Backend: `gd_private.registration_gate.is_open=true` con audit; `invite_only_enabled=false`.
2. Frontend: `registrationMode:'public'`, `registrationEnabled:true`, `turnstileSiteKey:'SITE_KEY_PUBBLICA_VERIFICATA'`.

La funzione server non contiene chiavi segrete né richiede di esporne in GitHub. Se uno dei controlli fallisce, **richiudere** il gate e ripristinare il frontend. Non trattare il pilota come pubblico prima di completare questi requisiti.
