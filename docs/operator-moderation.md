# GoodDiner · Verifica ristoranti e moderazione riservata

**Stato:** procedure amministrative tecnicamente predisposte. Non sono un servizio clienti, non sostituiscono la verifica documentale e non autorizzano il lancio pubblico senza informativa GDPR, operatore responsabile e collaudi reali.

**Solo progetto Supabase GoodDiner:** `ixczkhmvbjszgmlqznlk` (organizzazione dedicata). **Non usare EasyGart/Gartenarte, DopoTurno o Sindru.**

## Accesso da iPhone

Apri Safari, accedi alla [SQL Editor del progetto GoodDiner](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/sql) usando le autorizzazioni interne dell'organizzazione. Non incollare password, service-role key, documenti o fotografie personali in GitHub, chat pubbliche o codice frontend.

Le funzioni `gd_private.review_merchant_application` e `gd_private.resolve_guest_dispute` sono volutamente **non esposte** alla Data API. Possono essere eseguite solo dal ruolo proprietario `postgres` nell'editor interno. Ogni decisione è registrata in `gd_private.operator_audit`. Il campo `operator_label` deve identificare un incaricato autorizzato e verificabile tramite i controlli organizzativi interni. Il log applicativo non è un sostituto dei log di accesso amministratore.

## 1. Verifica ristorante

**Prima del controllo SQL:** identificare il responsabile della richiesta; verificare che gestisca realmente il locale con fonte indipendente e documentazione idonea; verificare l'email confermata. Una scheda Google Maps non costituisce prova. Conservare solo le prove necessarie, in archivio protetto e secondo regole di conservazione approvate.

Elenco richieste:

```sql
select a.id, a.restaurant_name, a.city, a.status, a.created_at,
       u.email, u.email_confirmed_at
from public.merchant_applications a
join auth.users u on u.id=a.applicant_id
where a.status='pending'
order by a.created_at asc;
```

Dopo la verifica *umana* sostituisci UUID, identificativo operatore e nota con dati reali. **Non approvare per prova.**

```sql
select gd_private.review_merchant_application(
  '00000000-0000-0000-0000-000000000000'::uuid,
  true,
  'operatore-autorizzato',
  'Esito della verifica indipendente della titolarita, registrato in archivio riservato.'
);
```

Per **rifiutare**, usare `false` al posto di `true` e motivare la decisione. In caso di approvazione, la procedura crea in modo atomico il ristorante con `verified_at`, aggiorna lo stato richiesta e scrive il log; in caso di rifiuto non crea alcun locale. Un UUID inesistente, richiesta già valutata o account senza email confermata viene respinto. L'operatore non può approvare dall'app cliente.

Verifica della singola richiesta dopo l'intervento:

```sql
select a.id,a.status,a.reviewed_at,r.id as restaurant_id,r.verified_at
from public.merchant_applications a
left join public.restaurants r on r.application_id=a.id
where a.id='00000000-0000-0000-0000-000000000000'::uuid;
```

## 2. Contestazioni delle recensioni

La richiesta nasce dal cliente, che la vede come `pending`. **Non è una rimozione automatica**. L'operatore deve esaminare gli elementi della visita e applicare criteri trasparenti, non soltanto accettare o negare arbitrariamente la segnalazione.

```sql
select d.id, d.created_at, d.status, d.reason,
       rv.id as review_id, rv.rating, rv.comment, rv.status as review_status,
       v.checked_in_at, rt.name as restaurant_name
from public.disputes d
join public.reviews rv on rv.id=d.review_id
join public.visits v on v.id=rv.visit_id
join public.restaurants rt on rt.id=rv.restaurant_id
where d.status='pending'
order by d.created_at asc;
```

Accoglimento dopo istruttoria umana:

```sql
select gd_private.resolve_guest_dispute(
  '00000000-0000-0000-0000-000000000000'::uuid,
  true,
  'operatore-autorizzato',
  'Motivazione verificabile della decisione, senza dati sensibili non necessari.'
);
```

Per **respingerla**, usare `false` e motivare. Accettare una contestazione porta `reviews.status` a `removed`; i traguardi non ancora riscattati che non corrispondono più al numero di recensioni positive pubblicate passano a `suspended`. I premi già `redeemed` **non vengono modificati**. La procedura è atomica e blocca le doppie decisioni sullo stesso caso.

Non promettere al cliente tempi di moderazione non approvati. Prima del go-live servono responsabile incaricato, tempi di risposta, gestione delle prove, diritto di rettifica/cancellazione, assistenza e revisione legale.

## 3. Controlli e audit

```sql
select action_type,target_id,operator_label,created_at
from gd_private.operator_audit
order by created_at desc
limit 50;
```

```sql
select count(*) as richieste_in_attesa
from public.merchant_applications where status='pending';
select count(*) as contestazioni_in_attesa
from public.disputes where status='pending';
```

**Mai:** esporre queste funzioni tramite un'API pubblica; concedere EXECUTE a `anon` o `authenticated`; salvare documenti degli utenti nella repository GitHub; caricare dati dimostrativi nella banca dati reale.

## Limitazioni rimaste

- Nessun account reale e nessun locale verificato alla data della prima stesura: non esiste ancora prova end-to-end di accettazione/rifiuto con due utenti veri.
- Manca un backoffice dedicato per un team di moderazione. Per il collaudo interno sono disponibili soltanto operazioni esplicite via SQL Editor protetto.
- Non è ancora definita la policy commerciale di riattivazione di traguardi sospesi in seguito a nuove recensioni; i voucher non sono utilizzabili.
- Sono da completare registri del trattamento, base giuridica, informativa privacy, processi di cancellazione/retention e controlli antiabuso.
