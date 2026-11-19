/* GoodDiner V7.9: curated appearance settings for demo clients and venue staff.
 * Visual-only preferences are deliberately local. They never change reputation,
 * visit validity, profile identity or customer visibility/permissions. */
'use strict';
(() => {
  const KEY='gooddiner-demo-appearance-v79';
  const CHOICES={
    theme:['signature','sunset','night'],
    density:['comfortable','compact'],
    pass:['signature','coral','night'],
    venue:['signature','coral','night']
  };
  const DEFAULT={theme:'signature',density:'comfortable',pass:'signature',venue:'signature'};
  const safe=(v)=>esc(v);
  let appearance=read();
  function read(){
    try{
      const parsed=JSON.parse(localStorage.getItem(KEY)||'null');
      if(!parsed||typeof parsed!=='object')return {theme:'signature',density:'comfortable',passes:{},venue:'signature'};
      const passes={};
      if(parsed.passes&&typeof parsed.passes==='object'){
        for(const [id,value] of Object.entries(parsed.passes)){
          if(/^(GD|CL)-[A-Z0-9-]{3,25}$/.test(id)&&CHOICES.pass.includes(value))passes[id]=value;
        }
      }
      return {
        theme:CHOICES.theme.includes(parsed.theme)?parsed.theme:'signature',
        density:CHOICES.density.includes(parsed.density)?parsed.density:'comfortable',
        passes,
        venue:CHOICES.venue.includes(parsed.venue)?parsed.venue:'signature'
      };
    }catch{return {theme:'signature',density:'comfortable',passes:{},venue:'signature'};}
  }
  function selectedPass(){return appearance.passes[db.activeCustomer]||'signature';}
  function currentValue(kind){return kind==='pass'?selectedPass():appearance[kind];}
  function apply(){
    const el=document.documentElement;
    el.dataset.gdTheme=appearance.theme;
    el.dataset.gdDensity=appearance.density;
    el.dataset.gdPass=state.role==='customer'?selectedPass():'signature';
    el.dataset.gdVenue=state.role==='restaurant'?appearance.venue:'signature';
  }
  function persist(){
    try{localStorage.setItem(KEY,JSON.stringify(appearance));return true;}
    catch{return false;}
  }
  function iconMini(name){
    if(name==='spark')return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l2.3 6.7L21 12l-6.7 2.3L12 21l-2.3-6.7L3 12l6.7-2.3L12 3Z"/></svg>`;
    if(name==='circle')return `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="3"/></svg>`;
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h10M5 17h14"/></svg>`;
  }
  function option(kind,value,label,description,mark='circle'){
    const chosen=currentValue(kind)===value;
    return `<button type="button" class="gd9-option gd9-choice-${safe(value)} ${chosen?'is-selected':''}" data-gd-custom="choice" data-kind="${kind}" data-value="${value}" aria-pressed="${chosen}" aria-label="${safe(label)}">
       <span class="gd9-option-art" aria-hidden="true">${iconMini(mark)}</span><span class="gd9-option-copy"><strong>${safe(label)}</strong><small>${safe(description)}</small></span><span class="gd9-selected-indicator" aria-hidden="true"></span>
    </button>`;
  }
  function appearancePanel(){
    return `<section class="gd9-studio-section" aria-label="Aspetto dell'app">
      <div class="gd9-studio-header"><div><span class="gd9-kicker">GOODDINER / STUDIO</span><h3>La tua app, il tuo stile.</h3><p>Scegli un carattere visivo e lo spazio che preferisci. Puoi cambiare idea in ogni momento.</p></div><span class="gd9-studio-symbol" aria-hidden="true"><img src="/icons/mark-light.svg" alt=""></span></div>
      <div class="gd9-studio-group"><h4>Atmosfera dell'interfaccia</h4><div class="gd9-options gd9-three">
      ${option('theme','signature','Firma','Petrolio e corallo','circle')}
      ${option('theme','sunset','Alba','Caldo e luminoso','spark')}
      ${option('theme','night','Notte','Blu profondo e rame','lines')}
      </div></div>
      <div class="gd9-studio-group"><h4>Spaziatura delle schermate</h4><div class="gd9-options gd9-two">
      ${option('density','comfortable','Aria','Più spazio tra le sezioni','circle')}
      ${option('density','compact','Compatta','Più contenuti a colpo d’occhio','lines')}
      </div></div>
    </section>`;
  }
  function clientPanel(){
    const c=customer(db.activeCustomer);if(!c)return '';
    const name=safe(c.nickname),id=safe(c.id),initial=safe(c.nickname.trim().charAt(0).toLocaleUpperCase('it-IT')||'G');
    return `<section class="gd9-studio" aria-label="Personalizzazione GoodDiner">
      ${appearancePanel()}
      <section class="gd9-studio-section gd9-pass-section" aria-label="Personalizza il DinerPass">
        <div class="gd9-studio-header"><div><span class="gd9-kicker">DINERPASS / IL TUO SEGNO</span><h3>Un pass che ti somiglia.</h3><p>Cambia la finitura della tua tessera. Nickname, codice e valutazioni non vengono modificati.</p></div></div>
        <div class="gd9-pass-preview" aria-label="Anteprima del DinerPass"><div class="gd9-pass-top"><span>GOODDINER · DINERPASS</span><span class="gd9-pass-dot" aria-hidden="true"></span></div><div class="gd9-pass-preview-mid"><span class="gd9-initial" aria-hidden="true">${initial}</span><div><strong>${name}</strong><small>${id} · ANTEPRIMA</small></div></div><span class="gd9-pass-bottom">LA TUA REPUTAZIONE CONTA.</span></div>
        <div class="gd9-options gd9-three">
        ${option('pass','signature','Petrolio','La firma originale','circle')}
        ${option('pass','coral','Corallo','Calda e decisa','spark')}
        ${option('pass','night','Notte','Profonda ed essenziale','lines')}
        </div>
      </section>
      <div class="gd9-footnote"><span>Solo su questo dispositivo. Il QR personale, il codice cliente e i riconoscimenti non cambiano.</span><button type="button" data-gd-custom="reset" data-scope="customer">Ripristina stile</button></div>
    </section>`;
  }
  function venuePanel(){
    // A venue entered during onboarding is still unverified and only appears as a demo label.
    let venueName=N;
    try{const saved=JSON.parse(localStorage.getItem('gooddiner-demo-venue-v76')||'null');
      if(saved&&typeof saved.name==='string'&&saved.name.trim())venueName=saved.name.slice(0,80);
    }catch{}
    const venueMark=merchantPhotos?.logo?
      `<img src="${safe(merchantPhotos.logo)}" alt="Logo scelto dal ristoratore">`:
      `<span aria-hidden="true">GD</span>`;
    return `<section class="gd9-studio gd9-venue-studio" aria-label="Personalizzazione del locale">
      ${appearancePanel()}
      <section class="gd9-studio-section" aria-label="Identità visiva del ristorante">
        <div class="gd9-studio-header"><div><span class="gd9-kicker">STUDIO LOCALE</span><h3>Un locale riconoscibile.</h3><p>Personalizza gli accenti della tua scheda. Copertina, logo e fotografie restano quelli che carichi tu.</p></div></div>
        <div class="gd9-venue-preview"><span class="gd9-venue-logo">${venueMark}</span><div><small>ANTEPRIMA LOCALE · DEMO</small><strong>${safe(venueName)}</strong><span>${safe(storyTagline())}</span></div></div>
        <div class="gd9-options gd9-three">
          ${option('venue','signature','Petrolio','Raffinato','circle')}
          ${option('venue','coral','Corallo','Accogliente','spark')}
          ${option('venue','night','Notte','Contemporaneo','lines')}
        </div>
      </section>
      <div class="gd9-footnote"><span>Le scelte rimangono in questa demo. Non modificano l'identità verificata di un ristorante reale.</span><button type="button" data-gd-custom="reset" data-scope="venue">Ripristina stile</button></div>
    </section>`;
  }
  const baseClientProfile=clientProfile;
  const baseMerchantManage=merchantManage;
  const baseClientHome=clientHome;
  const baseMerchantHome=merchantHome;
  const baseRender=render;
  clientProfile=function(){
    const s=baseClientProfile();
    const anchor='<div class="section-heading"><h2>Prova un altro profilo';
    return s.includes(anchor)?s.replace(anchor,clientPanel()+anchor):s+clientPanel();
  };
  merchantManage=function(){
    const s=baseMerchantManage();
    const anchor='<div class="section-heading editorial-heading"><h2>L\'identità del tuo locale';
    return s.includes(anchor)?s.replace(anchor,venuePanel()+anchor):s+venuePanel();
  };
  clientHome=function(){
    const s=baseClientHome();
    const anchor='<section class="passport passport-interactive';
    return s.includes(anchor)?s.replace(anchor,'<div class="gd9-quick"><span>Il tuo DinerPass, il tuo stile.</span><button type="button" data-gd-custom="open" data-target="profile">Personalizza la tessera '+icon('arrow',14)+'</button></div>'+anchor):s;
  };
  merchantHome=function(){
    const s=baseMerchantHome();
    const anchor='<section class="merchant-feature';
    return s.includes(anchor)?s.replace(anchor,'<div class="gd9-quick gd9-merchant-quick"><span>Fai riconoscere il tuo locale.</span><button type="button" data-gd-custom="open" data-target="manage">Personalizza la scheda '+icon('arrow',14)+'</button></div>'+anchor):s;
  };
  render=function(){apply();baseRender();};
  function updateChoices(){
    document.querySelectorAll('[data-gd-custom="choice"]').forEach(button=>{
      const selected=currentValue(button.dataset.kind)===button.dataset.value;
      button.classList.toggle('is-selected',selected);
      button.setAttribute('aria-pressed',String(selected));
    });
  }
  function setChoice(kind,value){
    if(!Object.prototype.hasOwnProperty.call(CHOICES,kind)||!CHOICES[kind].includes(value))return;
    const before=JSON.stringify(appearance);
    if(kind==='pass')appearance.passes[db.activeCustomer]=value;
    else appearance[kind]=value;
    if(!persist()){
      appearance=JSON.parse(before);
      notify('Non riesco a salvare lo stile su questo dispositivo.');
      return;
    }
    apply();updateChoices();
    const label={theme:'Tema dell’app',density:'Spaziatura',pass:'DinerPass',venue:'Stile del locale'}[kind];
    document.querySelector('.gd9-live-message')?.remove();
    const live=document.createElement('span');live.className='gd9-live-message';live.setAttribute('role','status');live.textContent=label+' aggiornato';
    const area=document.querySelector('.gd9-studio');area?.appendChild(live);
    window.setTimeout(()=>live.remove(),2200);
  }
  function resetAppearance(scope){
    const before=JSON.stringify(appearance);
    if(scope==='customer'){
      appearance.theme=DEFAULT.theme;
      appearance.density=DEFAULT.density;
      delete appearance.passes[db.activeCustomer];
    }else if(scope==='venue'){
      appearance.theme=DEFAULT.theme;
      appearance.density=DEFAULT.density;
      appearance.venue=DEFAULT.venue;
    }else{return;}
    if(!persist()){
      appearance=JSON.parse(before);
      notify('Non riesco a salvare su questo dispositivo.');
      return;
    }
    apply();updateChoices();notify('Aspetto originale ripristinato.');
  }
  document.addEventListener('click',event=>{
    const btn=event.target.closest('[data-gd-custom]');if(!btn)return;
    const action=btn.dataset.gdCustom;
    if(action==='choice')setChoice(btn.dataset.kind,btn.dataset.value);
    if(action==='reset')resetAppearance(btn.dataset.scope);
    if(action==='open'){
      const target=btn.dataset.target;
      if(state.role==='customer'&&target==='profile'||state.role==='restaurant'&&target==='manage'){
        state.tab=target;render();
        const anchor=document.querySelector('.gd9-studio');
        window.requestAnimationFrame(()=>anchor?.scrollIntoView({block:'start',behavior:window.matchMedia?.('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'}));
      }
    }
  });
  window.addEventListener('storage',event=>{
    if(event.key!==KEY)return;
    appearance=read();apply();updateChoices();
  });
  apply();render();
})();