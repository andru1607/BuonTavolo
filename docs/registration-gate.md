# GoodDiner · Blocco iscrizioni lato server

**Progetto esclusivo:** Supabase GoodDiner `ixczkhmvbjszgmlqznlk`. Non modificare gli altri progetti.

## Perché esiste

La variabile `registrationEnabled: false` in `config.js` impedisce di aprire il modulo nell'app, **ma non blocca richieste HTTP dirette a Supabase Auth**. Per questo `database/gooddiner_registration_gate.sql` installa una protezione sul server, **chiusa per impostazione iniziale**.

Il trigger `gd_auth_registration_gate` controlla ogni nuova riga in `auth.users`, comprese registrazioni email, anonime e da API dirette. Quando la registrazione è chiusa, blocca l'inserimento con `GOODDINER_REGISTRATION_CLOSED`. Login, reset password e sessioni di account già esistenti non creano una nuova riga e non sono interessati. L'eventuale account creato tramite procedura amministrativa è comunque soggetto alla regola, a meno che il test transazionale non venga avviato come `postgres` con un'opzione locale esplicita.

La tabella `gd_private.registration_gate` non è esposta al browser. Il ruolo interno `supabase_auth_admin` può **soltanto leggerla**. Il cambio dello stato è consentito al proprietario del database e viene registrato in `gd_private.registration_gate_audit`, senza email, password o token.

## Verifica senza creare account

Apri da Safari il [SQL Editor GoodDiner](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/sql) e controlla:

```sql
select is_open,updated_at,changed_by,reason
from gd_private.registration_gate where singleton=true;
```

Il valore deve essere `false` finché il progetto non ha superato le verifiche. La prova tecnica del blocco diretto `supabase_auth_admin` viene registrata nel [registro di accettazione](go-live-acceptance.md); non usare un'email reale o dati di un cliente per testarlo.

## Aprire soltanto dopo l'approvazione

Prima di cambiare lo stato devono essere **tutte** vere queste condizioni:

1. Dominio HTTPS pubblico canonico verificato, redirect email/recovery configurati e smoke HTTP superato.
2. Provider email e SMTP realmente funzionanti, conferma account e recupero testati.
3. Cloudflare Turnstile attivato **anche in Supabase Auth**, con la secret key soltanto nelle impostazioni protette. Site key pubblica in `config.js`. Verificato il rifiuto di richieste API prive del token.
4. Flussi testati con account di volontari autorizzati su due dispositivi, inclusa fotocamera Safari e autorizzazioni incrociate.
5. Identità del titolare GDPR, informativa, base giuridica per i voti alle persone, moderazione e canale privacy esterno approvati.
6. Responsabile operativo designato per verifiche ristoratori e contestazioni. Controlli del nome/marchio completati.

Solo un amministratore autorizzato può eseguire **nell'editor protetto**:

```sql
update gd_private.registration_gate
set is_open=true,updated_at=now(),
    changed_by='identificativo-operatore-autorizzato',
    reason='Rilascio approvato dopo verifiche Auth, anti-bot, privacy e dispositivi'
where singleton=true and is_open=false;
```

**Non eseguire questo comando adesso.** Non aprire `config.js` prima della verifica del gate. Quando le condizioni saranno soddisfatte, impostare `registrationEnabled:true` e la site key pubblica; la secret key non deve essere committata.

Per richiudere immediatamente le nuove iscrizioni:

```sql
update gd_private.registration_gate
set is_open=false,updated_at=now(),
    changed_by='identificativo-operatore-autorizzato',
    reason='Sospensione cautelativa delle nuove registrazioni per verifica'
where singleton=true and is_open=true;
```

Per vedere le transizioni:

```sql
select is_open,changed_by,reason,created_at
from gd_private.registration_gate_audit order by created_at desc limit 30;
```

**Nota tecnica:** il trigger DB garantisce il blocco delle nuove righe anche se il modulo frontend viene aggirato. Un hook ufficiale Supabase `Before User Created` può in futuro aggiungere messaggi di errore più chiari, ma non è richiesto per far rispettare questo blocco. I test SQL di RLS usano una deroga locale limitata alla sessione `postgres`, con rollback completo; la deroga non è disponibile agli utenti dell'app.

**Importante:** la conversione di un account anonimo in un account permanente richiede anche l'abilitazione del *manual identity linking* nelle impostazioni Supabase, secondo la [documentazione ufficiale Anonymous Sign-Ins](https://supabase.com/docs/guides/auth/auth-anonymous). Il flusso email è `updateUser({email})`, conferma dell'indirizzo, quindi `updateUser({password})`. Non dichiarare questo percorso verificato finché non è provato su account reali.
