# Manager: avanzamento registro unico
- Registro telefonico, walk-in, lista d'attesa del locale e modifiche con audit. Gli ospiti esterni non hanno profili fittizi e non maturano automaticamente buoni.
- Auto-conferma opzionale, soltanto con tavolo singolo compatibile e nessuna prenotazione sovrapposta senza tavolo; altrimenti conferma manuale. Le prenotazioni manuali richiedono assegnazione e arrivo. Le modifiche liberano l'assegnazione precedente conservando il buono.
- Spostamento tavoli con pointer events in modalità disposizione, alternativa riga/colonna. Griglia non canvas libero. Verifica su iPhone ancora necessaria.
- Test SQL con rollback: registro telefonico, lista d'attesa, modifica audit, accesso isolato e conferma automatica. La protezione aggiuntiva per prenotazioni senza tavolo va collaudata separatamente. Nessuna notifica push implementata; notifiche interne già presenti.
- Prossimi: collaudo browser/iPhone, lista d'attesa cliente, assegnazione automatica combinazioni di tavoli, push reali, staff, report e widget esterno. Gate recensioni/sconti invariati.
