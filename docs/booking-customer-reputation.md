# Reputazione del cliente da prenotazione — requisito di prodotto

Confermato il 26/11/2026: il ristorante che riceve una prenotazione GoodDiner deve poter aprire il profilo del cliente e consultare le valutazioni condivisibili ricevute in altri locali. Non è uno storico pubblico, né una ricerca libera per nickname.

## Interfaccia
Agenda > prenotazione online attiva > Profilo cliente > valutazioni con nome locale, voto e data; ritorno all'agenda. Le prenotazioni telefoniche e walk-in senza account collegato non offrono accesso alla reputazione. La demo mostra dati fittizi; in produzione il pulsante comunica che la funzione è in preparazione, non interroga recensioni di terzi.

## Contratto backend da implementare e verificare
- RPC dedicata che accetta soltanto ID prenotazione, risolve il cliente sul server e verifica proprietario del locale, email verificata, licenza valida, prenotazione online reale e stato/validità temporale.
- Abilitazione separata e disattivata per impostazione predefinita. Informativa specifica, autorizzazione valida e revocabile del cliente, nessuna condivisione retroattiva di dati raccolti come privati. Riesame legale e privacy prima dell'abilitazione.
- Restituire soltanto recensioni ammesse alla condivisione, pubblicate su visite confermate, escludendo contestazioni pendenti/accolte e dati non necessari; niente punteggio aggregato o decisione automatica di accettazione/rifiuto.
- Audit consultabile dal cliente, limiti di frequenza, controllo della revoca al momento di ciascuna lettura, scadenza della consultazione; niente cache persistente.
- Test negativi con altro ristorante, ID arbitrario, account cliente, booking manuale, prenotazione annullata o scaduta, mancata autorizzazione, revoca e recensione contestata. Test positivo con due locali verificati e cliente autorizzato.
- Non modificare gli account o i dati esistenti. Il progetto Supabase GoodDiner `ixczkhmvbjszgmlqznlk` non è autorizzato al connettore in questo ciclo; non usare EasyGart.

## Evidenza
Test simulato 26/11: agenda con prenotazione online e telefonica; un solo pulsante profilo, accesso telefonico rifiutato, apertura profilo con tre recensioni fittizie, ritorno all'agenda e pulizia dello stato; SDK reale non inizializzato. Nessuna verifica di accesso dati reali.
