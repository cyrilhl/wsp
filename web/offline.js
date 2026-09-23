(() => {
  let status = 'Preparing offline access…';
  let pending = false;
  window.meterOfflineStatus = () => status;
  async function verifyController() {
    const controller = navigator.serviceWorker.controller;
    if (!controller || !controller.scriptURL.endsWith('/meter-sw.js')) return;
    const channel = new MessageChannel();
    channel.port1.onmessage = event => {
      status = event.data.ready ? 'Ready offline' : 'Offline setup failed. Reconnect and retry.';
      channel.port1.close();
    };
    controller.postMessage('CHECK_READY', [channel.port2]);
  }
  window.meterRetryOffline = async () => {
    if (pending) return;
    if (!('serviceWorker' in navigator) || !window.isSecureContext) {
      status = 'Offline setup requires HTTPS or localhost.';
      return;
    }
    pending = true;
    status = 'Preparing offline access…';
    try {
      const registration = await navigator.serviceWorker.register('meter-sw.js');
      const watch = candidate => {
        if (!candidate) return;
        candidate.addEventListener('statechange', () => {
          if (candidate.state === 'redundant' && !navigator.serviceWorker.controller) status = 'Offline setup failed. Reconnect and retry.';
          if (candidate.state === 'activated') verifyController();
        });
      };
      watch(registration.installing);
      registration.addEventListener('updatefound', () => watch(registration.installing));
      await verifyController();
    } catch (_) { status = 'Offline setup failed. Use the prepared release build, reconnect and retry.'; }
    finally { pending = false; }
  };
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener('controllerchange', verifyController);
  window.meterRetryOffline();
})();
