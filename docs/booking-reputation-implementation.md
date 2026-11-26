# Consultazione da prenotazione: implementazione predisposta, non attiva

## Stato del 26/11/2026
- Frontend: RPC `read_booking_reputation` collegata al pulsante Profilo cliente; gestione di indisponibilità, autorizzazione negata, risposta obsoleta dopo cambio sessione, scadenza della prenotazione e chiusura dopo massimo 120 secondi o passaggio in background.
- Cliente: scelta facoltativa per singola prenotazione online tramite `set_booking_reputation_choice`; revoca e registro consultazioni tramite `my_booking_reputation_accesses`.
- Database: `database/gooddiner_booking_reputation_draft.sql` è una **bozza SQL non applicata**, con gate separato disattivato per default. Non è una migrazione verificata.
- Config browser `bookingReputationEnabled:false`; configurazione reale invariata. Il progetto GoodDiner non è accessibile al connettore (permesso negato), EasyGart non va usato.
- Test mirati: sintassi, flag off, predicati SQL statici, mock RPC con ID prenotazione soltanto, ristorante estraneo e prenotazione manuale rifiutati, risposta autorizzata, voto invalido filtrato, chiusura in background, autorizzazione negata, cambio account, scelta e revoca. Nessun test SQL reale.

## Condizioni per l'attivazione
1. Ricollegare Supabase GoodDiner `ixczkhmvbjszgmlqznlk`. Ispezionare schema, fonte online e proprietà delle prenotazioni, funzione di verifica email/licenza, RLS, revoca e indici. Confermare che la lista cliente restituisca `source`.
2. Approvare base giuridica, valutazione privacy e testo definitivo della scelta specifica (la stringa booking-reputation-v1 è un identificatore tecnico, non una prova di approvazione). Nessun riutilizzo automatico del consenso preliminare.
3. Verificare l'evidenza di autorizzazione della visita sorgente, la procedura di revoca e l'interruttore QR esistente. Le recensioni storiche private non sono condivise retroattivamente. La bozza restituisce soltanto recensioni di visite con scelta di condivisione esplicita successiva all'approvazione; se non esistono, il risultato è vuoto. Non rimuovere questo controllo per popolare la lista.
4. Eseguire migrazione e prove transazionali con rollback su utenti fittizi: due ristoratori distinti, prenotazione online, autorizzazione, accesso consentito, accesso incrociato negato, revoca, annullamento/scadenza, contestazioni, limiti, access log, nessuna lettura anonima o diretta delle tabelle. Testare anche l'app su dispositivi reali autorizzati.
5. Soltanto dopo esito positivo e approvazione documentata, abilitare l'interruttore server e quello browser coordinatamente; aggiornare informativa, testi di stato e collaudare sul dominio canonico. Non utilizzare i dati per decisioni automatiche di ammissione.
