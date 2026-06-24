/**
 * auth-guard.js
 * Loaded first on index.html — redirects to auth.html if no valid session exists.
 */
(function () {
  const session = sessionStorage.getItem('ds_session');
  if (!session) {
    window.location.replace('auth.html');
  }
})();
