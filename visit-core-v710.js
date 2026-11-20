/* GoodDiner V7.10 - Pure, local-only visit display helpers. NOT a backend or proof of presence. */
(function(root){
  'use strict';
  const KEY='gooddiner-demo-attendance-v76';
  const VENUE_KEY='gooddiner-demo-venue-v76';
  const cleanText = (value, max=100) => String(value ?? '').trim().slice(0,max);
  const validRecord = record => record && typeof record==='object' &&
    typeof record.customerId==='string' && typeof record.restaurant==='string' &&
    typeof record.id==='string' && Number.isFinite(Number(record.at)) && Number(record.at)>0;
  const recordStatus = record => record?.status==='annullata' ? 'annullata' : 'confermata';
  function read(storage=root.localStorage){
    try{const raw=JSON.parse(storage.getItem(KEY)||'[]');return Array.isArray(raw)?raw.filter(validRecord).slice(0,100):[];}
    catch{return [];}
  }
  function venue(storage=root.localStorage){
    try{const raw=JSON.parse(storage.getItem(VENUE_KEY)||'null');
      const name=cleanText(raw?.name,80);return name || 'La Quercia';}
    catch{return 'La Quercia';}
  }
  const sorted = rows => [...rows].sort((a,b)=>Number(b.at)-Number(a.at));
  const byCustomer = (rows,id) => sorted(rows.filter(x=>x.customerId===id));
  const byVenue = (rows,name) => sorted(rows.filter(x=>x.restaurant===name));
  const active = row => recordStatus(row)==='confermata';
  const isoDay = (timestamp) => {const d=new Date(timestamp); if(!Number.isFinite(d.getTime()))return '';
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};
  function counts(rows, now=Date.now()){
    const day=isoDay(now),week=now-7*864e5;
    return {today:rows.filter(x=>active(x)&&(x.day||isoDay(Number(x.at)))===day).length,
      week:rows.filter(x=>active(x)&&Number(x.at)>=week&&Number(x.at)<=now).length,
      total:rows.filter(active).length, voided:rows.filter(x=>!active(x)).length};
  }
  function canCheckIn(rows, customerId, restaurant, day){
    return !rows.some(x=>x.customerId===customerId && x.restaurant===restaurant &&
      (x.day||isoDay(Number(x.at)))===day && active(x));
  }
  function voidDemo(storage,id,restaurant,now=Date.now()){
    const rows=read(storage);const index=rows.findIndex(x=>x.id===id&&x.restaurant===restaurant&&active(x));
    if(index<0)return false;
    const next=rows.map((x,i)=>i===index?{...x,status:'annullata',voidedAt:now}:x);
    try{storage.setItem(KEY,JSON.stringify(next));return true;}catch{return false;}
  }
  root.GoodDinerVisitsV710={KEY,VENUE_KEY,read,venue,sorted,byCustomer,byVenue,recordStatus,isoDay,counts,canCheckIn,voidDemo};
  if(typeof module!=='undefined'&&module.exports)module.exports=root.GoodDinerVisitsV710;
})(typeof window==='undefined'?globalThis:window);