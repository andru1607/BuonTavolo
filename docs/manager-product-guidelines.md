# GoodDiner Manager — indirizzo prodotto confermato 24/11/2026

Riferimento funzionale: TheFork Manager, non copia di brand, codice, contenuti o interfaccia proprietaria. Fonti ufficiali:
- https://www.theforkmanager.com/it/cosa-ti-offre-thefork-manager
- https://www.theforkmanager.com/it/blog/gestione-prenotazioni-ristorante
- https://www.theforkmanager.com/it/blog/thefork-manager-secondo-aggiornamento-del2026
- https://www.theforkmanager.com/it/blog/gestione-del-ristorante/guida-allutilizzo-di-thefork-manager-i-nuovi-partner

## Architettura UX obiettivo
Massimo quattro sezioni ristoratore: Agenda, Sala, Clienti, Gestione. Agenda prima delle configurazioni; azioni di servizio raggiungibili in pochi tocchi su iPhone. Non eliminare check-in DinerPass, storico, licenza o accessi attuali durante la transizione. Separare account cliente e merchant, Studio indipendente.

## Priorità in ordine
1. Agenda di servizio: vista oggi/domani, ricerca nominativo, stati, coperti, evidenza sconto; configurazione separata. Prima iterazione implementata.
2. Sala digitale: zone interno/esterno, numeri, posti, layout personalizzabile, stato reale, assegnazione manuale/automatica solo se compatibile, tavoli unibili, controllo concorrente e sovrapposizioni lato server.
3. Un solo registro per prenotazioni GoodDiner, telefono, walk-in e sito; non creare finti account o attribuire recensioni/premi a persone non registrate. Fonte e modifiche tracciate. Privacy e accessi minimi.
4. Disponibilità per servizio, turni e capacità, conferma automatica opt-in dopo verifica di tavoli/capienza; modifiche, lista d'attesa con conferma esplicita.
5. Riconferma e promemoria per ridurre no-show; push/email effettive solo dopo infrastruttura e consenso/condizioni appropriate. Nessun punteggio predittivo arbitrario, blacklist o penalità automatiche.
6. Clienti: solo informazioni necessarie ai rapporti con il proprio locale, accesso staff per ruolo, nessuna esposizione di recensioni personali di altri locali.
7. Report: prenotazioni/canale/servizio, coperti, occupazione, no-show, buoni riscattati. Studio aggregato verificabile.
8. Widget prenotazioni per sito locale, eventuali integrazioni esterne solo con API e autorizzazioni reali.

## Identità e regole
GoodDiner Rewards: un premio per dieci valutazioni 8–10 su visite confermate, buono monouso riservabile con prenotazione, sconto visibile al ristoratore. I gate delle valutazioni personali e degli sconti rimangono off finché non sono soddisfatti i requisiti privacy/legali e commerciali già documentati. Non inventare offerte, notifiche consegnate, integrazioni o test su iPhone. Non intervenire su altri progetti. Prima di ogni release: test autorizzazioni, dati reali, regressioni e mobile; verificare deploy.
