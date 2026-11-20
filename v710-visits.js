/* GoodDiner V7.10 - A legible visit journey on both sides of the demo.
   All data is local, fictional and intentionally not authoritative. */
'use strict';
(() => {
  if(typeof GoodDinerVisitsV710==='undefined'||typeof clientHome!=='function'||typeof merchantHome!=='function')return;
  const V=GoodDinerVisitsV710;
  const safe=value=>esc(value);
  let filter='today',searchTerm='';
  const currentVenue=()=>V.venue(localStorage);
  const guestRows=()=>V.byCustomer(V.read(localStorage),db.activeCustomer);
  const merchantRows=()=>V.byVenue(V.read(localStorage),currentVenue());
  function when(row){const time=Number(row.at),date=new Date(time);
    return Number.isFinite(date.getTime())?new Intl.DateTimeFormat('it-IT',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(date):'Data non disponibile';}
  const active=row=>V.recordStatus(row)==='confermata';
  function visitCard(row,customer=false){
    const canceled=!active(row);
    const name=customer?row.restaurant:row.nickname;
    return `<article class="gd10-visit ${canceled?'gd10-void':''}">
      <span class="gd10-visit-symbol" aria-hidden="true">${icon(customer?'home':'user',19)}</span>
      <div class="gd10-visit-info"><strong>${safe(name||'Profilo demo')}</strong><small>${safe(when(row))} · ${customer?'Visita':'ID '+safe(row.customerId)}</small></div>
      <span class="gd10-status ${canceled?'gd10-status-void':''}">${canceled?'Annullata':'Registrata'}</span>
      ${customer?'':`<button type="button" class="gd10-detail" data-gd10="detail" data-id="${safe(row.id)}" aria-label="Dettagli visita di ${safe(row.nickname)}">${icon('arrow',17)}</button>`}
    </article>`;
  }
  function clientHistory(full=false){
    const all=guestRows(),shown=full?all:all.slice(0,3),activeRows=all.filter(active);
    return `<section class="gd10-section gd10-customer" aria-label="Storico delle mie presenze">
      <div class="gd10-heading"><div><span class="gd10-kicker">DINERPASS / LE MIE VISITE</span>
        <h2>${full?'Le tue presenze.':'Ogni visita conta.'}</h2><p>Registrazioni della demo su questo dispositivo, separate dalle recensioni.</p></div>
        <span class="gd10-total" aria-label="${activeRows.length} ${activeRows.length===1?'presenza confermata':'presenze confermate'}">${activeRows.length}<small>${activeRows.length===1?'visita':'visite'}</small></span></div>
      ${shown.length?`<div class="gd10-list">${shown.map(x=>visitCard(x,true)).join('')}</div>`:
        `<div class="gd10-empty">${icon('scan',25)}<strong>Nessuna visita ancora.</strong><span>Quando un ristoratore scansiona il tuo DinerPass nella demo, la presenza comparirà qui.</span></div>`}
      ${!full&&all.length>3?`<button type="button" class="gd10-view-all" data-gd10="history">Apri tutto lo storico ${icon('arrow',16)}</button>`:''}
      ${full?'<p class="gd10-note">Puoi vedere anche le presenze annullate per ricostruire ciò che è accaduto nella demo.</p>':''}
    </section>`;
  }
  function merchantFilterRows(){
    const now=Date.now(),today=V.isoDay(now),week=now-7*864e5;
    return merchantRows().filter(row=>{
      if(filter==='today'&&(row.day||V.isoDay(Number(row.at)))!==today)return false;
      if(filter==='week'&&Number(row.at)<week)return false;
      const query=searchTerm.trim().toLocaleLowerCase('it-IT');
      return !query||`${row.nickname||''} ${row.customerId||''}`.toLocaleLowerCase('it-IT').includes(query);
    });
  }
  const resultCount=n=>n+' '+(n===1?'risultato':'risultati');
  function listMarkup(){const all=merchantFilterRows();
    return all.length?all.map(row=>visitCard(row)).join(''):
      `<div class="gd10-empty">${icon('search',24)}<strong>Nessuna presenza per questa ricerca.</strong><span>Modifica i filtri oppure scansiona un DinerPass.</span></div>`;
  }
  function merchantRegister(){
    const all=merchantRows(),n=V.counts(all);
    const recent=all.find(x=>active(x)&&Date.now()-Number(x.at)<120000&&Number(x.at)<=Date.now());
    return `<section class="gd10-section gd10-register" id="gd10-register" aria-label="Registro presenze del locale">
      <div class="gd10-heading"><div><span class="gd10-kicker">REGISTRO / ${safe(currentVenue().toLocaleUpperCase('it-IT'))}</span>
        <h2>Le presenze, in ordine.</h2><p>Consulta le scansioni del locale e correggi eventuali registrazioni errate.</p></div></div>
      ${recent?`<div class="gd10-receipt" role="status">${icon('check',19)} <div><strong>Ultima presenza registrata</strong><span>${safe(recent.nickname)} · ${safe(when(recent))}</span></div></div>`:''}
      <div class="gd10-stats" aria-label="Riepilogo delle presenze"><div><strong>${n.today}</strong><span>Oggi</span></div><div><strong>${n.week}</strong><span>Ultimi 7 giorni</span></div><div><strong>${n.total}</strong><span>Totale</span></div></div>
      <div class="gd10-toolbar"><div class="gd10-filters" role="group" aria-label="Periodo delle presenze">
        ${[['today','Oggi'],['week','7 giorni'],['all','Tutte']].map(([value,label])=>`<button type="button" data-gd10="filter" data-filter="${value}" aria-pressed="${filter===value}">${label}</button>`).join('')}
      </div><label class="gd10-search">${icon('search',18)}<span class="sr-only">Cerca per nickname o ID</span><input type="search" id="gd10-search" autocomplete="off" placeholder="Cerca un ospite" value="${safe(searchTerm)}"></label></div>
      <div class="gd10-result-count" aria-live="polite">${resultCount(merchantFilterRows().length)}</div>
      <div class="gd10-list" id="gd10-rows">${listMarkup()}</div>
      <p class="gd10-note">Dati inventati, salvati soltanto in questo browser. Le presenze annullate restano visibili per chiarezza.</p>
    </section>`;
  }
  const originalClientHome=clientHome,originalClientProfile=clientProfile,originalMerchantHome=merchantHome;
  clientHome=function(){
    const markup=originalClientHome();const anchor='<section class="reward-feature">';
    return markup.includes(anchor)?markup.replace(anchor,clientHistory()+anchor):markup+clientHistory();
  };
  clientProfile=function(){
    const markup=originalClientProfile(),anchor='<div class="section-heading"><h2>Privacy e dati';
    return markup.includes(anchor)?markup.replace(anchor,clientHistory(true)+anchor):markup+clientHistory(true);
  };
  merchantHome=function(){
    const markup=originalMerchantHome(),anchor='<section class="merchant-feature';
    // Replace the older five-row preview with a real filterable demo register.
    const old=/<div class="gd-visit-title">[\s\S]*?<p class="gd-privacy-line">Solo questa sessione browser\.[\s\S]*?<\/p>/;
    if(old.test(markup))return markup.replace(old,merchantRegister());
    return markup.includes(anchor)?markup.replace(anchor,merchantRegister()+anchor):markup+merchantRegister();
  };
  function refreshRegister(){
    const host=document.getElementById('gd10-register');if(!host)return;
    const counts=V.counts(merchantRows());
    const stats=host.querySelector('.gd10-stats');
    if(stats)stats.innerHTML=`<div><strong>${counts.today}</strong><span>Oggi</span></div><div><strong>${counts.week}</strong><span>Ultimi 7 giorni</span></div><div><strong>${counts.total}</strong><span>Totale</span></div>`;
    host.querySelectorAll('[data-gd10="filter"]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===filter)));
    const results=merchantFilterRows(),box=host.querySelector('#gd10-rows');if(box)box.innerHTML=listMarkup();
    const count=host.querySelector('.gd10-result-count');if(count)count.textContent=resultCount(results.length);
  }
  let lastFocus=null;
  function openDetail(id){
    const row=merchantRows().find(r=>r.id===id);if(!row)return;
    lastFocus=document.activeElement;
    const el=document.createElement('div');el.className='gd10-overlay';el.id='gd10-detail-overlay';
    el.innerHTML=`<div class="gd10-dialog" role="dialog" aria-modal="true" aria-labelledby="gd10-dialog-title">
      <div class="gd10-dialog-head"><div><span class="gd10-kicker">DETTAGLIO PRESENZA / DEMO</span><h2 id="gd10-dialog-title">${safe(row.nickname)}</h2></div><button class="gd10-close" data-gd10="close" type="button" aria-label="Chiudi dettaglio">${icon('close',22)}</button></div>
      <div class="gd10-detail-rows"><div><span>Ristorante</span><strong>${safe(row.restaurant)}</strong></div><div><span>Codice cliente</span><strong>${safe(row.customerId)}</strong></div><div><span>Registrata il</span><strong>${safe(when(row))}</strong></div><div><span>Stato</span><strong>${active(row)?'Registrata · demo':'Annullata · demo'}</strong></div></div>
      <p class="gd10-note">Questa è soltanto una simulazione locale, non una conferma di presenza reale.</p>
      ${active(row)?`<button type="button" class="gd10-cancel" data-gd10="void" data-id="${safe(row.id)}">Annulla presenza demo</button>`:''}
      <p id="gd10-void-error" role="status"></p>
      <button type="button" class="gd10-done" data-gd10="close">Chiudi</button>
    </div>`;
    document.body.appendChild(el);el.querySelector('.gd10-close')?.focus({preventScroll:true});
  }
  function closeDetail(){document.getElementById('gd10-detail-overlay')?.remove();lastFocus?.focus?.({preventScroll:true});}
  document.addEventListener('click',event=>{
    if(event.target.id==='gd10-detail-overlay'){closeDetail();return;}
    const button=event.target.closest?.('[data-gd10]');if(!button)return;
    if(button.dataset.gd10==='filter'){
      filter=['today','week','all'].includes(button.dataset.filter)?button.dataset.filter:'today';refreshRegister();
    }else if(button.dataset.gd10==='history'){
      if(state.role!=='customer')return;
      state.tab='profile';render();
      window.requestAnimationFrame(()=>document.querySelector('.gd10-customer')?.scrollIntoView({block:'start',behavior:window.matchMedia?.('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'}));
    }else if(button.dataset.gd10==='detail'&&state.role==='restaurant'){
      openDetail(button.dataset.id);
    }else if(button.dataset.gd10==='close'){
      closeDetail();
    }else if(button.dataset.gd10==='void'&&state.role==='restaurant'){
      const row=merchantRows().find(r=>r.id===button.dataset.id);if(!row)return;
      if(!window.confirm('Annullare questa presenza nella demo? Rimarrà nello storico con stato Annullata.'))return;
      if(V.voidDemo(localStorage,row.id,currentVenue())){
        closeDetail();render();notify('Presenza demo annullata. Lo storico è stato conservato.');
      }else {
        const error=document.getElementById('gd10-void-error');
        if(error)error.textContent='Annullamento non salvato. Chiudi il dettaglio e ricontrolla la presenza nel registro.';
      }
    }
  });
  document.addEventListener('input',event=>{
    if(event.target.id!=='gd10-search')return;
    searchTerm=event.target.value.slice(0,80);refreshRegister();
  });
  document.addEventListener('keydown',event=>{
    const overlay=document.getElementById('gd10-detail-overlay');if(!overlay)return;
    if(event.key==='Escape'){event.preventDefault();closeDetail();return;}
    if(event.key==='Tab'){
      const focusable=[...overlay.querySelectorAll('button:not([disabled])')];
      if(!focusable.length)return;
      const first=focusable[0],last=focusable[focusable.length-1];
      if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
      else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
    }
  });
  render();
})();