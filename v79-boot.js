/* GoodDiner V7.9: only public visual settings. No personal identifiers or authentication. */
(() => {
  'use strict';
  const KEY='gooddiner-demo-appearance-v79';
  const values={theme:['signature','sunset','night'],density:['comfortable','compact']};
  try{
    const stored=JSON.parse(localStorage.getItem(KEY)||'null')||{};
    const root=document.documentElement;
    root.dataset.gdTheme=values.theme.includes(stored.theme)?stored.theme:'signature';
    root.dataset.gdDensity=values.density.includes(stored.density)?stored.density:'comfortable';
  }catch{
    document.documentElement.dataset.gdTheme='signature';
    document.documentElement.dataset.gdDensity='comfortable';
  }
})();