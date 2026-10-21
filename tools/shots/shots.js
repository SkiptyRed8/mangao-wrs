// Takes phone-size screenshots of the app for the documentation (Chapter 9, Appendix G).
// Runs on GitHub Actions (.github/workflows/screenshots.yml): Java server with demo data on :3100,
// the Flutter web build on :5100. Output: tools/shots/out/*.png and log.txt
const { chromium } = require('playwright');
const fs = require('fs');
const API = 'http://localhost:3100';
const APP = 'http://localhost:5100/';
const OUT = __dirname + '/out';
fs.mkdirSync(OUT, { recursive: true });
const log = [];
const say = (...a) => { const s = a.join(' '); console.log(s); log.push(s); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Android phone size (720 x 1600 pixels, like a Samsung A-series): 360 x 800 dp, minus the status bar
// (34 dp) and the navigation bar (48 dp) that frame.py draws around each picture afterwards.
const W = 360, H = 718;

async function api(method, path, body, token) {
  const r = await fetch(API + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) say('API', method, path, r.status, JSON.stringify(j).slice(0, 200));
  return j;
}
const login = (phone, password) => api('POST', '/api/auth/login', { phone, password });

async function seed() {
  const owner = await login('09170000001', 'owner123');
  const staff = await login('09170000002', 'staff123');
  const rider = await login('09170000003', 'rider123');
  const ana = await login('09172001111', 'ana123');
  const pin = (lat, lng, street) => ({ mode: 'pin', lat, lng, street, barangay: 'Commonwealth', landmark: 'Near the chapel' });
  const a1 = await api('POST', '/api/orders', { type: 'Refill', quantity: 3, phone: '09172001111', address: pin(14.6985, 121.0905, 'Malaya St.') }, ana.token);
  const accounts = await api('GET', '/api/staff', null, owner.token);
  const juan = (accounts.accounts || []).find((u) => /Juan/.test(u.name || ''));
  const board = await api('GET', '/api/admin/orders?view=new', null, owner.token);
  const maria = (board.orders || []).find((o) => /Maria/.test(o.name));
  const ids = [a1.order && a1.order.id, maria && maria.id].filter(Boolean);
  await api('POST', '/api/admin/orders/accept', { ids, riderId: juan && juan.id }, owner.token);
  await api('POST', '/api/work/walk-in', { quantity: 3, type: 'Refill', paid: true }, staff.token);
  await api('POST', '/api/work/walk-in', { quantity: 1, type: 'Package', paid: false, name: 'Aling Rosa' }, staff.token);
  const ben = await api('POST', '/api/work/delivery', { name: 'Ben Cruz', phone: '09185552211', address: '5 Sampaguita St., Batasan Hills', quantity: 2, channel: 'Call' }, staff.token);
  const todo = await api('GET', '/api/work/todo', null, staff.token);
  await api('POST', '/api/work/out', { ids: (todo.processing || []).map((o) => o.id) }, staff.token);
  await api('POST', '/api/rider/location', { lat: 14.6952, lng: 121.0880 }, rider.token);
  if (maria) await api('POST', `/api/rider/orders/${maria.id}/delivered`, { paid: true }, rider.token);
  await api('POST', '/api/orders', { type: 'Package', quantity: 1, phone: '09172001111', address: pin(14.6975, 121.0921, 'Kalayaan St.') }, ana.token);
  say('seeded: ana order', a1.order && a1.order.id, 'maria', maria && maria.id, 'ben', ben.order && ben.order.id, 'juan', juan && juan.id);
  return { owner, staff, rider, ana };
}

async function open(browser, session) {
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    geolocation: { latitude: 14.6952, longitude: 121.088 }, permissions: ['geolocation'] });
  if (session) {
    await ctx.addInitScript(([t, u]) => {
      localStorage.setItem('flutter.token', JSON.stringify(t));
      localStorage.setItem('flutter.user', JSON.stringify(JSON.stringify(u)));
    }, [session.token, session.user]);
  }
  const page = await ctx.newPage();
  page.on('pageerror', (e) => say('pageerror', e.message.slice(0, 150)));
  await page.goto(APP, { waitUntil: 'load' });
  await sleep(6000);
  await page.evaluate(() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); });
  await sleep(800);
  return { ctx, page };
}

async function shot(page, name, wait = 1500) {
  // Move the pointer off the tab bar so no tooltip stays on the picture.
  await page.mouse.move(W / 2, 330);
  await sleep(wait + 1500);
  await page.screenshot({ path: `${OUT}/${name}.png` });
  say('shot', name);
}

async function tap(page, text) {
  const tries = [
    page.getByRole('button', { name: text }),
    page.getByRole('tab', { name: text }),
    page.getByText(text, { exact: true }),
    page.getByText(text),
    page.locator(`[aria-label*="${text}"]`),
  ];
  for (const l of tries) {
    try {
      if ((await l.count()) > 0) { await l.first().click({ timeout: 3000, force: true }); await sleep(1500); say('tap', text, 'ok'); return true; }
    } catch (e) { /* next */ }
  }
  say('tap', text, 'NOT FOUND');
  return false;
}

// Bottom tab by position (works without semantics).
async function tab(page, i, n) {
  await page.mouse.click(Math.round(((i + 0.5) * W) / n), H - 40);
  await sleep(1800);
}

(async () => {
  const s = await seed();
  const browser = await chromium.launch();

  // Welcome and login screens
  let { ctx, page } = await open(browser, null);
  await shot(page, '01-welcome');
  if (await tap(page, 'Log in')) await shot(page, '02-login');
  await ctx.close();
  ({ ctx, page } = await open(browser, null));
  if (await tap(page, 'Sign up')) await shot(page, '03-signup');
  await ctx.close();

  // Customer
  ({ ctx, page } = await open(browser, s.ana));
  await shot(page, '10-customer-home');
  if (await tap(page, 'Order Now')) await shot(page, '11-order-form');
  await ctx.close();
  ({ ctx, page } = await open(browser, s.ana));
  await tab(page, 1, 3);
  await shot(page, '12-my-orders');
  if (await tap(page, 'Out for delivery')) await shot(page, '13-order-tracking', 5000);
  await ctx.close();
  ({ ctx, page } = await open(browser, s.ana));
  await tab(page, 2, 3);
  await shot(page, '14-customer-account');
  await ctx.close();

  // Owner
  ({ ctx, page } = await open(browser, s.owner));
  await shot(page, '20-owner-home');
  await tab(page, 1, 5);
  await shot(page, '21-order-board');
  if (await tap(page, 'Pedro Reyes')) await shot(page, '22-order-details');
  await ctx.close();
  ({ ctx, page } = await open(browser, s.owner));
  await tab(page, 1, 5);
  if (await tap(page, 'Live Map')) await shot(page, '23-live-map', 6000);
  await ctx.close();
  ({ ctx, page } = await open(browser, s.owner));
  await tab(page, 2, 5);
  await shot(page, '24-inventory');
  if (await tap(page, 'Movement History')) await shot(page, '25-movement-history');
  await ctx.close();
  ({ ctx, page } = await open(browser, s.owner));
  await tab(page, 3, 5);
  await shot(page, '26-sales-daily');
  if (await tap(page, 'Weekly')) await shot(page, '27-sales-weekly');
  await ctx.close();
  ({ ctx, page } = await open(browser, s.owner));
  await tab(page, 4, 5);
  await shot(page, '28-more');
  if (await tap(page, 'Staff & Riders')) await shot(page, '29-staff-riders');
  await ctx.close();
  ({ ctx, page } = await open(browser, s.owner));
  if ((await tap(page, 'Notifications')) || (await tap(page, 'Alerts'))) await shot(page, '30-notifications');
  await ctx.close();
  ({ ctx, page } = await open(browser, s.owner));
  if (await tap(page, 'Log Walk-in')) await shot(page, '31-log-walkin');
  await ctx.close();

  // Staff
  ({ ctx, page } = await open(browser, s.staff));
  await shot(page, '40-staff-todo');
  await tab(page, 2, 4);
  await shot(page, '41-staff-done-today');
  await ctx.close();

  // Rider
  ({ ctx, page } = await open(browser, s.rider));
  await shot(page, '50-rider-deliveries');
  await tab(page, 1, 4);
  await shot(page, '52-rider-live-map', 6000);
  await tab(page, 2, 4);
  await shot(page, '51-rider-done-today');
  await ctx.close();

  await browser.close();
  fs.writeFileSync(`${OUT}/log.txt`, log.join('\n'));
})().catch((e) => { console.error(e); fs.writeFileSync(`${OUT}/log.txt`, log.join('\n') + '\n' + e.stack); process.exit(1); });
