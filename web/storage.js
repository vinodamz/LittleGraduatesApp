// Browser outbox and cached shelf lists. No credentials are stored here.
(() => {
  const db = new Promise((resolve, reject) => {
    const request = indexedDB.open('little-graduates', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('records');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const transaction = async (mode, operation) => {
    const database = await db;
    return new Promise((resolve, reject) => {
      const tx = database.transaction('records', mode);
      const result = operation(tx.objectStore('records'));
      tx.oncomplete = () => resolve(result.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error('Browser storage unavailable'));
    });
  };
  const locks = new Map();
  window.lgStore = {
    lock: async owner => {
      if (locks.has(owner)) return true;
      if (!navigator.locks) return false;
      return new Promise(resolve => {
        navigator.locks.request('lg-materials:' + owner, {ifAvailable: true}, async lock => {
          if (!lock) { resolve(false); return; }
          const held = new Promise(release => locks.set(owner, release));
          resolve(true);
          await held;
        }).catch(() => resolve(false));
      });
    },
    release: owner => { const release = locks.get(owner); if (release) { locks.delete(owner); release(); } },
    read: async key => (await transaction('readonly', store => store.get(key))) || '',
    write: async (key, value) => { await transaction('readwrite', store => store.put(value, key)); },
    remove: async key => { await transaction('readwrite', store => store.delete(key)); },
  };
})();
