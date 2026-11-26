# GoodDiner — DPIA preliminare e decisione di rilascio
26 novembre 2026. Bozza tecnica non approvata, non parere legale. Condivisione reale disabilitata.

## Trattamento e finalità
Valutazioni di comportamenti osservabili legati a visite confermate, consultazione facoltativa da un altro ristorante verificato dopo check-in. Interessati: clienti, titolari, operatori. Dati: identificativo interno, nickname, visita, voto, data, locale, scelta del QR, log accesso. Testi liberi non condivisi. Supabase e Vercel: verificare ruoli contrattuali, DPA, ubicazione, subfornitori e trasferimenti. I dati personali non devono essere usati per finalità estranee, marketing o liste nere.

## Necessità e proporzionalità
Alternativa sempre disponibile: visita senza divulgazione. Nessun punteggio globale, accesso pubblico, ricerca per nome o ammissione automatica. Una lettura entro 5 minuti dalla scansione, schermata per 2 minuti, massimo 30 valutazioni degli ultimi 12 mesi. Solo fonti esplicitamente autorizzate, senza recensioni contestate in attesa o accolte. Revoca semplice per tutte le autorizzazioni precedenti. Non riutilizzare recensioni raccolte con la promessa di visibilità privata. Verificare se una finalità meno invasiva possa conseguire lo stesso risultato.

## Rischi e misure
| Rischio | Iniziale | Misura | Residuo da validare |
|---|---|---|---|
| Esclusione dal servizio, coercizione al QR | Alto | Nessun punteggio globale, alternativa senza condivisione, divieto contrattuale di penalizzazione, segnalazioni e sospensione locali | Alto finché non verificato sul campo |
| Diffamazione, discriminazione, errori | Alto | Visita verificata, una recensione, contestazione e sospensione della divulgazione, testo libero escluso | Medio-alto; serve moderatore e tempi |
| Consultazione non autorizzata | Alto | Licenza, verifica locale, token monouso, RLS, RPC con controllo proprietario, log e revoca | Medio; serve test indipendente |
| Conservazione e riutilizzo esterni | Alto | Minimizzazione, finestra temporale, divieto di copia/riutilizzo, cancellazione programmata da definire | Alto per screenshot e copie esterne |
| Minori o persone vulnerabili | Alto | Limitare condivisione agli adulti con verifica proporzionata da definire; nessuna apertura fino a valutazione | Alto |

## Base giuridica e diritti
Da determinare per ciascuna finalità (art. 6 GDPR). La scelta del QR non prova automaticamente un consenso libero: il locale non deve condizionare il servizio, né esercitare pressioni. Se il consenso è adottato, documentare scelta informata, specifica, revoca e assenza di svantaggi; se si valuta interesse legittimo, documentare necessità e bilanciamento, inclusa opposizione. Informativa artt. 13/14, diritti artt. 15–22, sicurezza art. 32, DPIA art. 35. Valutare art. 36 se resta rischio elevato, prima di iniziare il trattamento. Nessuna dichiarazione di conformità.

## Informativa breve da validare
Il QR normale registra la visita. Il QR facoltativo con condivisione permette al locale verificato di consultare alcune valutazioni precedentemente autorizzate e autorizza la futura valutazione di questa visita a essere inclusa nello storico condivisibile. La scelta non deve condizionare il servizio. Puoi revocare le autorizzazioni dal Profilo, consultare il registro e contestare una recensione. Le informazioni già viste da un locale non possono essere ritirate. Il testo integrale dell'informativa deve identificare titolare, recapiti, basi giuridiche, destinatari, conservazione, trasferimenti e diritti.

## Condizioni prima di aprire
- [ ] Identità e contatto del titolare, ruoli GoodDiner/locali e contratti, responsabili e trasferimenti.
- [ ] Valutazione legale e DPIA approvata dal titolare; consultazione interessati quando appropriata.
- [ ] Informativa completa, termini locali, età e prova di scelta libera. Nessuna penalizzazione per mancata condivisione.
- [ ] Responsabile moderazione, SLA, ricorsi, incidenti, processo per diritti e cancellazione; retention automatica e backup verificati.
- [ ] Collaudo iPhone con account autorizzati e verifica sicurezza indipendente.
- [ ] Se rischio residuo elevato, consultazione preventiva dell'autorità.
- [ ] Solo dopo esito documentato, approvazione esplicita e versione informativa definitiva: attivare i due gate. Fino ad allora anche le recensioni private richiedono la propria validazione prima dell'uso commerciale.

Fonti: https://eur-lex.europa.eu/legal-content/IT/TXT/?uri=CELEX:32016R0679 ; https://www.garanteprivacy.it/valutazione-d-impatto-della-protezione-dei-dati-dpia- ; https://www.garanteprivacy.it/home/docweb/-/docweb-display/docweb/9058979 ; https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en
