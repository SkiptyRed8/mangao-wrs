// Philippine time (UTC+8, no daylight saving) and the estimated delivery rule (Chapter 4):
// 30 minutes after the order is accepted or logged; orders accepted or logged from 11:30 to 12:00
// get 1:00 to 1:30 PM (lunch break).
const PH = 8 * 60 * 60 * 1000;

let fixedNow = null;
/** The current time (tests can set a fixed time). */
const now = () => (fixedNow ? new Date(fixedNow) : new Date());
/** For tests only: setNow('2026-10-14T11:40:00+08:00'), setNow(null) to go back to the real clock. */
const setNow = (iso) => {
  fixedNow = iso ? new Date(iso).getTime() : null;
};

/** Hours and minutes of a date in Philippine time. */
function phParts(d) {
  const p = new Date(d.getTime() + PH);
  return { y: p.getUTCFullYear(), mo: p.getUTCMonth(), d: p.getUTCDate(), h: p.getUTCHours(), mi: p.getUTCMinutes() };
}

/** A Philippine-time clock time on the same day as d. */
function phAt(d, h, mi) {
  const p = phParts(d);
  return new Date(Date.UTC(p.y, p.mo, p.d, h, mi) - PH);
}

/** { from, to } for an order accepted or logged at time t. from is null except for the lunch rule. */
function estimatedDelivery(t = now()) {
  const { h, mi } = phParts(t);
  const minutes = h * 60 + mi;
  if (minutes >= 11 * 60 + 30 && minutes < 12 * 60) return { from: phAt(t, 13, 0), to: phAt(t, 13, 30), lunch: true };
  return { from: null, to: new Date(t.getTime() + 30 * 60 * 1000), lunch: false };
}

/** 9:50 AM */
function clock(d) {
  if (!d) return '';
  const { h, mi } = phParts(new Date(d));
  return `${h % 12 === 0 ? 12 : h % 12}:${String(mi).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

/** "Delivery by 9:50 AM" or "Delivery 1:00 to 1:30 PM" */
function deliveryText(from, to) {
  if (!to) return '';
  if (from) return `${clock(from).replace(/ (AM|PM)$/, '')} to ${clock(to)}`;
  return `by ${clock(to)}`;
}

/** Start of today in Philippine time. */
const todayStart = () => phAt(now(), 0, 0);

module.exports = { now, setNow, phParts, phAt, estimatedDelivery, clock, deliveryText, todayStart };
