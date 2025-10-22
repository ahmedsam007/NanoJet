document.addEventListener('DOMContentLoaded', async () => {
  const api = (typeof browser !== 'undefined' ? browser : chrome);
  const toggle = document.getElementById('enable');
  const res = await api.storage.sync.get({ enabled: true });
  toggle.checked = !!res.enabled;
  toggle.addEventListener('change', async () => {
    await api.storage.sync.set({ enabled: toggle.checked });
  });
});


