'use strict';
const svgNS = 'http://www.w3.org/2000/svg';
// Synthetic coordinates and durations, never a user's location history.
const stays = [{x:160,y:240,minutes:90},{x:480,y:120,minutes:20},{x:820,y:180,minutes:180}];
const routes = [[[160,240],[240,240],[240,180],[400,180],[400,120],[480,120]],[[480,120],[640,120],[640,60],[800,60],[800,180],[820,180]]];
function svgElement(tag, attributes, parent) {
  const element = document.createElementNS(svgNS, tag);
  for (const [key,value] of Object.entries(attributes)) element.setAttribute(key, value);
  parent.append(element);
  return element;
}
for (const points of routes) svgElement('polyline', {points:points.map(p=>p.join(',')).join(' ')}, document.querySelector('#routes'));
stays.forEach((stay,index) => {
  svgElement('circle', {cx:stay.x,cy:stay.y,r:Math.sqrt(stay.minutes)*7,fill:'url(#heat)'}, document.querySelector('#heat-nodes'));
  svgElement('circle', {cx:stay.x,cy:stay.y,r:Math.sqrt(stay.minutes)*1.8}, document.querySelector('#stay-nodes'));
  const label = svgElement('text', {x:stay.x,y:stay.y+Math.sqrt(stay.minutes)*1.8+28}, document.querySelector('#stay-nodes'));
  label.textContent = `Place ${index+1}`;
});
document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => {
  const isTime = button.dataset.mode === 'time';
  document.querySelectorAll('[data-mode]').forEach(other=>other.setAttribute('aria-pressed', String(other===button)));
  document.querySelector('#routes').style.opacity = isTime ? '0' : '1';
  document.querySelector('#heat-nodes').toggleAttribute('hidden', !isTime);
  document.querySelector('#mode-caption').textContent = isTime ? 'Time · stay area weighted by duration' : 'Path · observed routes and duration-scaled stays';
}));
const tabs = [...document.querySelectorAll('[data-doc]')];
const viewer = document.querySelector('#reader');
const repo = 'https://github.com/simply-sunny/footsteps/blob/main/';
function loadDocument(tab) {
  const key = tab.dataset.doc;
  document.querySelector('#source-link').href = repo + key.toUpperCase() + '.md';
  tabs.forEach(other => {
    other.setAttribute('aria-selected', String(other === tab));
    other.tabIndex = other === tab ? 0 : -1;
  });
  viewer.setAttribute('aria-labelledby', tab.id);
  if (!window.marked || !window.DOMPurify || !window.FOOTSTEPS_DOCS) {
    viewer.textContent = 'The document reader could not load. Use “Read source” above to open this document on GitHub.';
    return;
  }
  const fragment = DOMPurify.sanitize(marked.parse(FOOTSTEPS_DOCS[key]), {RETURN_DOM_FRAGMENT:true, FORBID_TAGS:['img','picture','source','style'], FORBID_ATTR:['style']});
  for (const link of fragment.querySelectorAll('a[href]')) {
    const href = link.getAttribute('href');
    if (!/^(https?:|mailto:|#)/i.test(href)) link.href = new URL(href, repo).href;
  }
  viewer.replaceChildren(fragment);
  viewer.scrollTop = 0;
}
tabs.forEach((tab,index) => {
  tab.addEventListener('click',()=>loadDocument(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if(event.key === 'ArrowRight') next=(index+1)%tabs.length;
    if(event.key === 'ArrowLeft') next=(index+tabs.length-1)%tabs.length;
    if(event.key === 'Home') next=0;
    if(event.key === 'End') next=tabs.length-1;
    if(next !== undefined){event.preventDefault();tabs[next].focus();loadDocument(tabs[next]);}
  });
});
loadDocument(tabs[0]);
