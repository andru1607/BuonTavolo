// BuonTavolo V5 · Area reale predisposta, attiva solo con un database dedicato.
// La chiave pubblicabile Supabase è sicura da usare in frontend CON le policy RLS.
const cfg = window.BUONTAVOLO_PUBLIC_CONFIG || {};
const $ = id => document.getElementById(id);
const html = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const shortDate = value => new Date(value).toLocaleDateString('it-IT',{day:'numeric',month:'short',year:'numeric'});
const todayDate = value => new Date(value).toLocaleString('it-IT',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});
const badge = (text, kind='') => `<span class="badge ${kind}">${html(text)}</span>`;
const icon = (type) => {
  const icons = {
    home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z"/>',
    reviews:'<path d="M21 12a8 8 0 0 1-8 8H5l-2 2v-9a9 9 0 1 1 18-1z"/>',
    visit:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 8h2m4 0h2M8 12h2m4 0h2M8 16h8"/>',
    user:'<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    settings:'<circle cx="12" cy="12" r="4"/><path d="m12 2 2 2 3-1 1 3 3 2-1 3 1 3-3 2-1 3-3-1-2 2-2-2-3 1-1-3-3-2 1-3-1-3 3-2 1-3 3 1z"/>',
    gift:'<rect x="3" y="9" width="18" height="12" rx="1"/><path d="M12 9v12M3 13h18M12 9c-4-8-9-7-8-3 0 2 3 3 8 3zm0 0c4-8 9-7 8-3 0 2-3 3-8 3z"/>'
  };
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[type] || icons.user}</svg>`;
};
let sb;
let session = null;
let profile = null;
let restaurant = null;
let reviews = [];
let disputes = [];
let visits = [];
let activeTab = 'home';
let authMode = 'signup';
let chosenRole = 'customer';
let busy = false;
let recovery = false;
let selectedRating = 0;
let visitToken = null;
let accountError = '';
let notice = '';

function notify(message) {
  const el = $('toast');
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(notify.timer);
  notify.timer = setTimeout(()=>el.classList.remove('show'),3400);
}
function errorText(error) {
  const m = (error?.message || '').toLowerCase();
  if(m.includes('invalid login')||m.includes('invalid credentials')) return 'Email o password non corretti.';
  if(m.includes('email not confirmed')) return 'Conferma prima la tua email usando il link ricevuto.';
  if(m.includes('duplicate key')||m.includes('unique constraint')) return 'Questi dati risultano già registrati. Prova un altro nickname o contatta l’assistenza.';
  if(m.includes('codice_scaduto')) return 'Il codice visita è scaduto o già usato. Chiedi al cliente di generarne un altro.';
  if(m.includes('ristorante_non_verificato')) return 'Il ristorante deve essere verificato prima di registrare visite.';
  if(m.includes('permission denied')||m.includes('row-level security')) return 'Operazione non autorizzata. Controlla lo stato del profilo.';
  return (error?.message || 'Si è verificato un problema. Riprova.').slice(0,250);
}
function intro(title,subtitle,eyebrow='BuonTavolo'){
  return `<div class="eyebrow">${html(eyebrow)}</div><h1 class="headline">${html(title)}</h1><p class="small" style="margin-bottom:21px">${html(subtitle)}</p>`;
}
function renderNoBackend() {
  $('nav').classList.add('hidden');
  $('view').innerHTML = `${intro('Il tuo spazio sta prendendo forma.','L’area account è pronta nel codice, ma non accetta ancora registrazioni. Dobbiamo collegare il database separato di BuonTavolo.','Prossimo passo')}<div class="panel"><h2>Account e dati protetti</h2><p class="small">Abbiamo predisposto accesso, profili, visite verificate e recensioni. Fino al collegamento del database restano disattivati: non raccogliamo email e password.</p><div style="margin-top:19px"><a class="btn olive fill" href="/">Continua con la demo</a></div></div><div class="notice">Non inserire dati personali veri nella demo. Le informazioni che vedi lì sono inventate e salvate soltanto sul tuo dispositivo.</div>`;
}
function renderAuth() {
  $('nav').classList.add('hidden');
  if (recovery) {
    $('view').innerHTML = `${intro('Nuova password','Scegli una password sicura per il tuo account.')}<form class="panel stack" id="password-update"><div class="field"><label for="new-password">Nuova password</label><input id="new-password" name="password" type="password" autocomplete="new-password" minlength="8" required></div><button class="btn primary fill" type="submit">Aggiorna password</button></form>`;
    return;
  }
  let modeUI = `<div class="auth-tabs" role="tablist" aria-label="Accesso"><button data-mode="signup" role="tab" aria-selected="${authMode==='signup'}">Crea account</button><button data-mode="signin" role="tab" aria-selected="${authMode==='signin'}">Accedi</button></div>`;
  const roles = `<div class="field"><label>Scegli come usare BuonTavolo</label><div class="role-grid"><button type="button" class="role-card" data-role="customer" aria-pressed="${chosenRole==='customer'}"><strong>Cliente</strong><small>Ricevi recensioni e segui la reputazione</small></button><button type="button" class="role-card" data-role="merchant" aria-pressed="${chosenRole==='merchant'}"><strong>Ristoratore</strong><small>Registra visite e valuta i clienti</small></button></div></div>`;
  $('view').innerHTML = `${intro(authMode==='signup'?'Benvenuto a tavola.':'Bentornato.','Uno spazio personale, pensato per clienti e ristoratori. Pochi passaggi, tutto chiaro.')}
  <div class="panel">${modeUI}<form id="auth-form" class="stack">
  ${authMode==='signup'?roles+`<div class="field"><label for="nickname">Nickname</label><input id="nickname" name="nickname" minlength="3" maxlength="30" autocomplete="nickname" required placeholder="Come vuoi essere chiamato?"><span class="hint">Sarà visibile nelle recensioni collegate alle tue visite.</span></div>`:''}
  <div class="field"><label for="email">Email</label><input id="email" name="email" type="email" autocomplete="email" required placeholder="nome@esempio.it"></div>
  <div class="field"><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="${authMode==='signup'?'new-password':'current-password'}" minlength="8" required placeholder="Minimo 8 caratteri"></div>
  <button class="btn primary fill" type="submit">${authMode==='signup'?'Crea account':'Accedi'}</button>
  </form>${authMode==='signin'?`<button class="btn text fill" data-action="reset-password">Password dimenticata?</button>`:''}</div>
  <div class="notice">${authMode==='signup'?'Per pubblicare recensioni, i ristoratori devono completare una verifica manuale dell’attività.':'La demo e gli account reali restano separati.'}</div>`;
}
function navItems(){return profile?.role==='merchant'?[['home','Home','home'],['visits','Visite','visit'],['reviews','Recensioni','reviews'],['settings','Gestione','settings']]:[['home','Home','home'],['reviews','Recensioni','reviews'],['visit','Visita','visit'],['profile','Profilo','user']];}
function renderNav() {
  $('nav').classList.remove('hidden');
  $('nav').innerHTML = `<div class="bottom-inner">${navItems().map(([key,label,ico])=>`<button data-tab="${key}" aria-current="${activeTab===key?'page':'false'}">${icon(ico)}<span>${label}</span></button>`).join('')}</div>`;
}
function positiveReviews() { const claimed=new Set(disputes.filter(d=>d.status!=='rejected').map(d=>d.review_id));return reviews.filter(r=>r.status==='published'&&r.rating>=8&&!claimed.has(r.id)); }
function customerReviews() {
  const claimed=new Map(disputes.map(d=>[d.review_id,d]));
  return reviews.length?reviews.map(r=>`<div class="review"><div class="row between"><div class="grow"><h3>${html(r.restaurants?.name||'Ristorante')}</h3><div class="date">${shortDate(r.created_at)}</div></div><strong class="score">${r.rating}/10 ★</strong></div><p>${html(r.comment)}</p><div class="row between" style="margin-top:11px">${badge(r.rating>=8?'Positiva':'Non positiva',r.rating>=8?'':'wait')}${claimed.has(r.id)?badge('Contestazione inviata','warn'):`<button class="btn sm" data-dispute="${r.id}">Contesta</button>`}</div></div>`).join(''):'<p class="small">Non hai ancora recensioni. Il primo passo è creare un codice visita quando sei al ristorante.</p>';
}
function clientHome() {
  const positive=positiveReviews().length, remain=positive%10, progress=Math.round(remain*10);
  return `${intro('La tua reputazione.','Un riepilogo semplice delle visite ricevute, delle recensioni e dei premi.','Area cliente')}
  <section class="member"><small>PROFILO CLIENTE</small><h2>${html(profile.nickname)}</h2><small>Codice cliente ${html(profile.customer_code)}</small><div class="line"></div><div class="status">${reviews.length===0?'Inizia il tuo percorso':positive>=5?'Reputazione positiva':'Le tue prime esperienze'}</div></section>
  <div class="panel" style="margin-top:14px"><div class="metric"><div><h2>Verso il prossimo premio</h2><p class="small">Recensioni positive da 8 a 10</p></div><strong>${remain}/10</strong></div><div class="track"><div style="width:${progress}%"></div></div><p class="small">${positive===0?'La prima recensione positiva ti avvicina al premio.':`Ti mancano ${10-remain} recensioni positive per il prossimo traguardo.`} Premi maturati: <strong>${Math.floor(positive/10)}</strong>.</p><p class="hint" style="margin-top:9px">I buoni non sono ancora attivabili: richiedono accordi con i ristoranti aderenti.</p></div>
  <div class="section-title">Ultime recensioni</div><div class="panel">${customerReviews()}</div>`;
}
function clientVisit() {
  return `${intro('Una visita, un codice.','Mostra il codice al ristoratore soltanto quando sei nel locale.','Verifica visita')}
  <div class="panel stack"><h2>Conferma la tua visita</h2><p class="small">Il codice è valido 15 minuti, si usa una sola volta e permette soltanto a un ristorante verificato di registrare la visita.</p>
  ${visitToken?`<div><div class="eyebrow">Codice visita</div><div class="code">${html(visitToken.id)}</div><p class="small" style="margin-top:9px">Scade alle ${todayDate(visitToken.expires_at)}.</p></div><button class="btn fill" data-copy="${visitToken.id}">Copia codice</button>`:''}
  <button class="btn primary fill" data-action="make-token">${visitToken?'Genera un nuovo codice':'Genera codice visita'}</button></div>
  <div class="notice">Il nickname e il codice cliente, da soli, non autorizzano recensioni. Il ristoratore deve ricevere il codice visita monouso.</div>`;
}
function clientProfile() {
  return `${intro('Il tuo profilo.','Puoi correggere il nickname e gestire il tuo accesso.','Area personale')}
  <div class="panel stack"><div><div class="eyebrow">Identificativo cliente</div><div class="code">${html(profile.customer_code)}</div></div><form class="stack" id="nickname-form"><div class="field"><label for="profile-nickname">Nickname</label><input id="profile-nickname" name="nickname" value="${html(profile.nickname)}" minlength="3" maxlength="30" required></div><button class="btn olive fill" type="submit">Salva nickname</button></form></div><div class="panel stack"><h2>Il tuo account</h2><p class="small">Email: ${html(session.user.email)}</p><button class="btn fill" data-action="logout">Esci dall’account</button></div>`;
}
function customerPage(){switch(activeTab){case 'reviews':return `${intro('Le tue recensioni.','Solo tu puoi vedere le tue valutazioni, tranne i ristoratori autorizzati.','Area cliente')}<div class="panel">${customerReviews()}</div>`;case 'visit':return clientVisit();case 'profile':return clientProfile();default:return clientHome();}}
function merchantRegister() {
  return `${intro('Completa il tuo ristorante.','I dati dell’attività serviranno per la verifica prima di pubblicare recensioni.','Area ristoratore')}
  <div class="panel"><form class="stack" id="restaurant-form"><div class="field"><label for="business-name">Nome ristorante</label><input id="business-name" name="name" minlength="3" maxlength="100" autocomplete="organization" required placeholder="Es. Ristorante La Quercia"></div><div class="field"><label for="vat-number">Partita IVA / identificativo fiscale aziendale</label><input id="vat-number" name="vat" minlength="8" maxlength="25" required placeholder="Identificativo dell’attività"></div><button type="submit" class="btn primary fill">Invia richiesta di verifica</button></form></div><div class="notice">La registrazione non abilita automaticamente la pubblicazione. Un ristorante deve essere verificato da un amministratore.</div><button class="btn fill" data-action="logout">Esci</button>`;
}
function merchantPending() {
  return `${intro('Richiesta ricevuta.','Il ristorante è registrato, ma la pubblicazione resta disattivata fino alla verifica.','Area ristoratore')}
  <div class="panel stack"><div class="row between"><h2>${html(restaurant.name)}</h2>${badge('In attesa','wait')}</div><p class="small">Identificativo attività: ${html(restaurant.vat_number)}.</p><p class="small">Non puoi ancora cercare profili, collegare visite o pubblicare recensioni. Questo evita che un account non verificato possa valutare persone.</p><button class="btn fill" data-action="refresh">Aggiorna stato</button></div><button class="btn fill" data-action="logout">Esci dall’account</button>`;
}
function merchantVisits() {
  return `${intro('Registra una visita.','Chiedi al cliente il codice temporaneo e usalo qui.','Area ristoratore')}
  <div class="panel stack"><h2>Collega un cliente</h2><p class="small">Il codice viene creato dal cliente e scade dopo 15 minuti. È necessario per collegare una visita verificata.</p><form id="claim-form" class="stack"><div class="field"><label for="visit-code">Codice visita ricevuto</label><input id="visit-code" name="token" inputmode="text" autocapitalize="none" autocomplete="off" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" required></div><button class="btn primary fill" type="submit">Verifica e registra</button></form></div>
  <h2 class="section-title">Visite recenti</h2><div class="panel">${merchantVisitRows()}</div>`;
}
function merchantVisitRows() {
  return visits.length?visits.map(v=>`<div class="compact"><div class="row between"><div class="grow"><h3>${html(v.customer_nickname)}</h3><div class="small">${html(v.customer_code)} · ${shortDate(v.created_at)}</div></div>${reviews.some(r=>r.visit_id===v.id)?badge('Recensita'):badge('Da recensire','wait')}</div>${!reviews.some(r=>r.visit_id===v.id)?`<button class="btn olive fill" style="margin-top:12px" data-review-visit="${v.id}">Recensisci la visita</button>`:''}</div>`).join(''):'<p class="small">Nessuna visita collegata. Usa il codice temporaneo mostrato dal cliente.</p>';
}
function merchantReviewForm(visitId){
  const v=visits.find(v=>v.id===visitId);if(!v)return '';
  return `<div class="panel stack" id="review-editor"><div class="row between"><h2>Nuova recensione</h2><button class="btn sm" data-action="close-review">Chiudi</button></div><p class="small">Cliente: <strong>${html(v.customer_nickname)}</strong><br>Visita: ${shortDate(v.created_at)}</p><form id="review-form" class="stack"><input type="hidden" name="visitId" value="${v.id}"><div class="field"><label>Valutazione da 1 a 10</label><div class="rating-grid">${Array.from({length:10},(_,i)=>`<button type="button" class="rating" data-rating="${i+1}" aria-pressed="${selectedRating===i+1}">${i+1} ★</button>`).join('')}</div><div class="rating-note">${selectedRating?selectedRating>=8?'Valutazione positiva: conta per il traguardo.':'Valutazione non positiva: non conta per il traguardo.':'Scegli il voto. Sono positive solo le valutazioni da 8 a 10.'}</div></div><div class="field"><label for="review-text">Descrivi il comportamento durante la visita</label><textarea id="review-text" name="comment" minlength="10" maxlength="1200" required placeholder="Usa soltanto fatti osservabili e un linguaggio rispettoso."></textarea></div><button class="btn primary fill" type="submit">Pubblica recensione</button></form><div class="notice">Non inserire dati sanitari, accuse non verificate o caratteristiche personali sensibili.</div></div>`;
}
let editingVisitId = null;
function merchantReviews() {
  return `${intro('Recensioni ai clienti.','Recensisci soltanto visite collegate a un codice verificato.','Area ristoratore')}${editingVisitId?merchantReviewForm(editingVisitId):''}<h2 class="section-title">Visite da recensire</h2><div class="panel">${merchantVisitRows()}</div>
  <h2 class="section-title">Recensioni pubblicate</h2><div class="panel">${reviews.length?reviews.map(r=>`<div class="review"><div class="row between"><div><strong>${html(visits.find(v=>v.id===r.visit_id)?.customer_nickname||'Cliente')}</strong><div class="date">${shortDate(r.created_at)}</div></div><strong class="score">${r.rating}/10 ★</strong></div><p>${html(r.comment)}</p>${badge(r.rating>=8?'Positiva':'Non positiva',r.rating>=8?'':'wait')}</div>`).join(''):'<p class="small">Le valutazioni effettuate compariranno qui.</p>'}</div>`;
}
function merchantSettings() {
  return `${intro('Il tuo ristorante.','Stato della verifica e informazioni professionali.','Gestione')}
  <div class="panel stack"><div class="row between"><h2>${html(restaurant.name)}</h2>${badge('Verificato')}</div><p class="small">P. IVA / codice: ${html(restaurant.vat_number)}</p><p class="small">Le note condivise tra ristoratori e gli abbonamenti non sono ancora attivi.</p></div>
  <div class="panel stack"><h2>Accesso</h2><p class="small">${html(session.user.email)}</p><button class="btn fill" data-action="logout">Esci</button></div>`;
}
function merchantHome() {
  const pending=visits.filter(v=>!reviews.some(r=>r.visit_id===v.id)).length;
  return `${intro(`Benvenuto, ${restaurant.name}.`,'Tutto quello che serve per valutare una visita, senza complicazioni.','Area ristoratore')}
  <div class="panel"><div class="row between"><div><h2>Visite da recensire</h2><p class="small">Solo clienti con visita verificata</p></div><strong style="font:32px Georgia,serif;color:var(--olive)">${pending}</strong></div><button class="btn primary fill" style="margin-top:16px" data-tab="visits">Registra una visita</button></div><h2 class="section-title">Attività recente</h2><div class="panel">${merchantVisitRows()}</div>`;
}
function merchantPage(){if(!restaurant)return merchantRegister();if(!restaurant.verified_at)return merchantPending();switch(activeTab){case 'visits':return merchantVisits();case 'reviews':return merchantReviews();case 'settings':return merchantSettings();default:return merchantHome();}}
function renderApp(){renderNav();$('view').innerHTML=profile.role==='merchant'?merchantPage():customerPage();}
function renderLoading(){ $('view').innerHTML='<div class="loading"><span class="spinner"></span>Caricamento in corso…</div>';}
async function loadData(){
  if(!session)return;
  renderLoading();
  const user=session.user;
  const prof=await sb.from('profiles').select('id,role,nickname,customer_code,created_at').eq('id',user.id).single();
  if(prof.error)throw prof.error;
  profile=prof.data;
  if(profile.role==='merchant'){
    const rs=await sb.from('restaurants').select('id,owner_id,name,vat_number,verified_at').eq('owner_id',user.id).maybeSingle();
    if(rs.error)throw rs.error;
    restaurant=rs.data;
    if(restaurant&&restaurant.verified_at){
      const [v,r]=await Promise.all([
        sb.from('visits').select('id,customer_id,customer_nickname,customer_code,created_at').eq('restaurant_id',restaurant.id).order('created_at',{ascending:false}).limit(50),
        sb.from('reviews').select('id,visit_id,customer_id,restaurant_id,rating,comment,created_at,status').eq('restaurant_id',restaurant.id).order('created_at',{ascending:false}).limit(50)
      ]);
      if(v.error)throw v.error;if(r.error)throw r.error;
      visits=v.data||[];reviews=r.data||[];
    }
  }else{
    const [r,d]=await Promise.all([
      sb.from('reviews').select('id,visit_id,restaurant_id,rating,comment,created_at,status,restaurants(name)').eq('customer_id',user.id).order('created_at',{ascending:false}).limit(200),
      sb.from('disputes').select('review_id,status').eq('customer_id',user.id)
    ]);
    if(r.error)throw r.error;if(d.error)throw d.error;
    reviews=r.data||[];disputes=d.data||[];
  }
  renderApp();
}
async function start(){
  const url=cfg.supabaseUrl||'';
  const key=cfg.supabasePublishableKey||'';
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url)||!key){renderNoBackend();return;}
  try{
    const module=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm');
    sb=module.createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
    sb.auth.onAuthStateChange((event, next)=>{
      if(event==='PASSWORD_RECOVERY'){recovery=true;renderAuth();return;}
      // Non eseguire chiamate Supabase sincrone da questo callback.
      if(event==='SIGNED_OUT') {session=null;profile=null;restaurant=null;renderAuth();}
    });
    const {data,error}=await sb.auth.getSession();
    if(error)throw error;
    session=data.session;
    if(session)await loadData();else renderAuth();
  }catch(err){ $('nav').classList.add('hidden');$('view').innerHTML=`${intro('Servizio temporaneamente non disponibile.','Non abbiamo potuto avviare l’accesso. Riprova più tardi.')}<div class="notice alert">${html(errorText(err))}</div><a class="btn olive fill" href="/">Apri la demo</a>`; }
}
async function handleAuth(form){
  if(busy)return;
  const data=new FormData(form), email=String(data.get('email')||'').trim(), password=String(data.get('password')||'');
  if(password.length<8)return notify('Usa una password di almeno 8 caratteri.');
  busy=true;
  try{
    if(authMode==='signup'){
      const nickname=String(data.get('nickname')||'').trim();
      if(nickname.length<3||nickname.length>30)return notify('Nickname: da 3 a 30 caratteri.');
      const result=await sb.auth.signUp({email,password,options:{emailRedirectTo:location.origin+'/account.html',data:{nickname,role:chosenRole}}});
      if(result.error)throw result.error;
      if(result.data.session){session=result.data.session;await loadData();}
      else {$('view').innerHTML=`${intro('Controlla la tua email.','Per completare la registrazione apri il collegamento che ti abbiamo inviato.')}<div class="panel stack"><p class="small">Se non arriva, controlla anche lo spam. Dopo la conferma torna su BuonTavolo ed effettua l’accesso.</p><button class="btn olive fill" data-mode="signin">Vai all’accesso</button></div>`;}
    }else{
      const result=await sb.auth.signInWithPassword({email,password});
      if(result.error)throw result.error;
      session=result.data.session;
      await loadData();
    }
  }catch(err){notify(errorText(err));}
  finally{busy=false;}
}
async function runOperation(fn){if(busy)return;busy=true;try{await fn();}catch(e){notify(errorText(e));}finally{busy=false;}}

document.addEventListener('click',async e=>{
  const mode=e.target.closest('[data-mode]');
  if(mode){authMode=mode.dataset.mode;renderAuth();return;}
  const role=e.target.closest('[data-role]');
  if(role){chosenRole=role.dataset.role;renderAuth();return;}
  const tab=e.target.closest('[data-tab]');
  if(tab){activeTab=tab.dataset.tab;editingVisitId=null;selectedRating=0;renderApp();scrollTo({top:0,behavior:'instant'});return;}
  const rating=e.target.closest('[data-rating]');
  if(rating){selectedRating=Number(rating.dataset.rating);const comment=$('review-text')?.value||'';renderApp();if($('review-text'))$('review-text').value=comment;return;}
  const review=e.target.closest('[data-review-visit]');
  if(review){editingVisitId=review.dataset.reviewVisit;selectedRating=0;activeTab='reviews';renderApp();scrollTo({top:0,behavior:'instant'});return;}
  const dispute=e.target.closest('[data-dispute]');
  if(dispute){const reason=prompt('Scrivi il motivo della contestazione (minimo 10 caratteri). Non includere dati sensibili.');if(!reason)return;if(reason.trim().length<10)return notify('Spiega il motivo con almeno 10 caratteri.');
    await runOperation(async()=>{const result=await sb.from('disputes').insert({review_id:dispute.dataset.dispute,customer_id:session.user.id,reason:reason.trim()});if(result.error)throw result.error;notify('Contestazione inviata.');await loadData();});return;
  }
  const copy=e.target.closest('[data-copy]');if(copy){try{await navigator.clipboard.writeText(copy.dataset.copy);notify('Codice copiato.');}catch{notify('Seleziona e copia il codice dalla scheda.');}return;}
  const action=e.target.closest('[data-action]');if(!action)return;
  switch(action.dataset.action){
    case 'reset-password':{
      const email=prompt('Inserisci la tua email per ricevere il link di ripristino.');if(!email)return;
      await runOperation(async()=>{const r=await sb.auth.resetPasswordForEmail(email.trim(),{redirectTo:location.origin+'/account.html'});if(r.error)throw r.error;notify('Se l’indirizzo è registrato, riceverai le istruzioni via email.');});break;
    }
    case 'make-token':await runOperation(async()=>{const r=await sb.from('visit_tokens').insert({customer_id:session.user.id}).select('id,expires_at').single();if(r.error)throw r.error;visitToken=r.data;renderApp();notify('Codice creato. Valido 15 minuti.');});break;
    case 'logout':await runOperation(async()=>{const r=await sb.auth.signOut();if(r.error)throw r.error;session=null;profile=null;restaurant=null;visitToken=null;editingVisitId=null;renderAuth();});break;
    case 'refresh':await runOperation(async()=>{await loadData();notify('Stato aggiornato.');});break;
    case 'close-review':editingVisitId=null;selectedRating=0;renderApp();break;
  }
});

document.addEventListener('submit',async e=>{
  e.preventDefault();const form=e.target;
  if(form.id==='auth-form'){await handleAuth(form);return;}
  if(form.id==='password-update'){await runOperation(async()=>{const password=new FormData(form).get('password');if(String(password).length<8)return notify('Password troppo corta.');const r=await sb.auth.updateUser({password});if(r.error)throw r.error;recovery=false;notify('Password aggiornata.');if(session)await loadData();else renderAuth();});return;}
  if(form.id==='nickname-form'){await runOperation(async()=>{const nickname=String(new FormData(form).get('nickname')||'').trim();if(nickname.length<3)return notify('Il nickname deve avere almeno 3 caratteri.');const r=await sb.from('profiles').update({nickname}).eq('id',session.user.id);if(r.error)throw r.error;await loadData();notify('Nickname aggiornato.');});return;}
  if(form.id==='restaurant-form'){await runOperation(async()=>{const data=new FormData(form);const name=String(data.get('name')||'').trim(),vat=String(data.get('vat')||'').trim();const r=await sb.from('restaurants').insert({owner_id:session.user.id,name,vat_number:vat});if(r.error)throw r.error;await loadData();notify('Richiesta di verifica registrata.');});return;}
  if(form.id==='claim-form'){await runOperation(async()=>{const token=String(new FormData(form).get('token')||'').trim();if(!/^[0-9a-fA-F-]{36}$/.test(token))return notify('Inserisci il codice visita completo.');const r=await sb.rpc('claim_visit',{p_token:token,p_restaurant_id:restaurant.id});if(r.error)throw r.error;activeTab='visits';await loadData();notify('Visita registrata.');});return;}
  if(form.id==='review-form'){await runOperation(async()=>{
    const data=new FormData(form),v=visits.find(x=>x.id===String(data.get('visitId'))),comment=String(data.get('comment')||'').trim();
    if(!v)return notify('Visita non trovata.');if(selectedRating<1||selectedRating>10)return notify('Seleziona da 1 a 10 stelle.');if(comment.length<10)return notify('Descrivi la visita con almeno 10 caratteri.');
    const r=await sb.from('reviews').insert({visit_id:v.id,customer_id:v.customer_id,restaurant_id:restaurant.id,rater_id:session.user.id,rating:selectedRating,comment});
    if(r.error)throw r.error;editingVisitId=null;selectedRating=0;await loadData();notify('Recensione pubblicata.');
  });}
});
start();