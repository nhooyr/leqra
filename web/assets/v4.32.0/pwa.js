(() => {
'use strict';
if (!('serviceWorker' in navigator) || !['http:', 'https:'].includes(location.protocol)) return;
window.addEventListener('load', () => {
  navigator.serviceWorker.register('assets/v4.32.0/sw.js', {scope: '/'}).catch(() => {});
}, {once: true});
})();
