// Export Report (FR-10; Admin Sales 4): the daily, weekly and unpaid accounts reports as a PDF
// (pdfkit) or a spreadsheet (exceljs). Money in the PDF is written "P1,310.00" (the PDF fonts have no peso sign).
const path = require('path');
const fs = require('fs');
const PDFDocument = require('pdfkit');
const ExcelJS = require('exceljs');
const { query } = require('../db');
const { dayRange, daySummary, dayOrders, addDays, mondayOf, weekSummary, change } = require('./reports');
const { unpaidAccounts, KEYED_ORDERS, UNPAID } = require('./customers');
const { phParts, now } = require('./time');

const STATION = 'Mangao Water Refilling Station';
const BLUE = '#0A84E0';
const LOGO = path.join(__dirname, '..', '..', 'assets', 'logo.png');
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const money = (v) => `P${Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const dateLabel = (ymd) => {
  const [y, m, d] = ymd.split('-').map(Number);
  return `${MONTHS[m - 1]} ${d}, ${y}`;
};
const ymdOf = (date) => {
  const p = phParts(date);
  return `${p.y}-${String(p.mo + 1).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
};
const clockOf = (date) => {
  if (!date) return '';
  const p = phParts(new Date(date));
  const h = p.h % 12 || 12;
  return `${h}:${String(p.mi).padStart(2, '0')} ${p.h < 12 ? 'AM' : 'PM'}`;
};
const phoneText = (p) => (/^\d{11}$/.test(p || '') ? `${p.slice(0, 4)} ${p.slice(4, 7)} ${p.slice(7)}` : p || '');
const pct = (v) => (v === null ? 'No sales last week' : v === 0 ? 'Same as last week' : `${v > 0 ? '+' : ''}${v}%`);

/**
 * The report as plain data: title, subtitle, summary rows [label, value, kind] and tables
 * { title, columns: [{ header, key, width, kind }], rows }. kind 'money' formats as pesos.
 */
async function buildReport(report, date) {
  const today = ymdOf(now());
  if (report === 'daily') {
    const [start, end] = dayRange(date);
    const s = await daySummary(start, end);
    const orders = await dayOrders(start, end);
    return {
      fileBase: `Mangao-Daily-Sales-${date}`,
      title: 'Daily Sales Report',
      subtitle: dateLabel(date),
      summary: [
        ['Money earned', s.moneyEarned, 'money'],
        ['Unpaid', s.unpaid, 'money'],
        ['Gallons processed', s.gallons],
        ['Packages sold', s.packages],
        ['Delivery gallons', s.deliveryGallons],
        ['Walk-in gallons', s.walkInGallons],
        ['Rider paid', s.riderPaid, 'money'],
        ['Orders completed', s.delivered + s.walkIns],
      ],
      tables: [
        {
          title: 'Orders',
          columns: [
            { header: 'Order', key: 'id', width: 8 },
            { header: 'Time', key: 'time', width: 10 },
            { header: 'Customer', key: 'name', width: 26 },
            { header: 'Gallons', key: 'quantity', width: 9, kind: 'num' },
            { header: 'Type', key: 'type', width: 10 },
            { header: 'Amount', key: 'total', width: 13, kind: 'money' },
            { header: 'Payment', key: 'tag', width: 16 },
          ],
          rows: orders.map((o) => ({ ...o, id: `#${o.id}`, time: clockOf(o.at) })),
        },
      ],
    };
  }
  if (report === 'weekly') {
    const start = mondayOf(date);
    const week = await weekSummary(start, today);
    const last = await weekSummary(addDays(start, -7), today);
    const t = week.totals;
    const l = last.totals;
    return {
      fileBase: `Mangao-Weekly-Sales-${start}`,
      title: 'Weekly Sales Report',
      subtitle: `${dateLabel(start)} to ${dateLabel(addDays(start, 6))}`,
      summary: [
        ['Money earned', t.moneyEarned, 'money'],
        ['Last week', l.moneyEarned, 'money'],
        ['Change in money earned', pct(change(t.moneyEarned, l.moneyEarned))],
        ['Gallons processed', t.gallons],
        ['Gallons last week', l.gallons],
        ['Packages sold', t.packages],
        ['Orders completed', t.orders],
        ['Unpaid', t.unpaid, 'money'],
        ['Rider paid', t.riderPaid, 'money'],
      ],
      tables: [
        {
          title: 'Day by day',
          columns: [
            { header: 'Day', key: 'day', width: 7 },
            { header: 'Date', key: 'dateText', width: 14 },
            { header: 'Money earned', key: 'moneyEarned', width: 15, kind: 'money' },
            { header: 'Last week', key: 'lastWeek', width: 13, kind: 'money' },
            { header: 'Gallons', key: 'gallons', width: 9, kind: 'num' },
            { header: 'Orders', key: 'orders', width: 8, kind: 'num' },
            { header: 'Unpaid', key: 'unpaid', width: 12, kind: 'money' },
          ],
          rows: week.days.map((d, i) => ({ ...d, dateText: dateLabel(d.date), lastWeek: last.days[i].moneyEarned })),
        },
      ],
    };
  }
  // unpaid accounts (as of now)
  const customers = await unpaidAccounts('');
  const orders = await query(
    `SELECT k.order_id, k.ckey, k.order_type, k.quantity, k.total_amount, COALESCE(k.delivered_at, k.created_at) AS at
     FROM ${KEYED_ORDERS} k WHERE ${UNPAID} ORDER BY at`
  );
  const nameOf = Object.fromEntries(customers.map((c) => [c.key, c.name]));
  return {
    fileBase: `Mangao-Unpaid-Accounts-${today}`,
    title: 'Unpaid Accounts',
    subtitle: `As of ${dateLabel(today)}`,
    summary: [
      ['Total owed', customers.reduce((a, c) => a + c.owed, 0), 'money'],
      ['Customers', customers.length],
      ['Unpaid orders', orders.length],
    ],
    tables: [
      {
        title: 'Customers',
        columns: [
          { header: 'Customer', key: 'name', width: 26 },
          { header: 'Phone', key: 'phone', width: 15 },
          { header: 'Unpaid orders', key: 'orders', width: 14, kind: 'num' },
          { header: 'Owed', key: 'owed', width: 13, kind: 'money' },
          { header: 'Oldest', key: 'oldestText', width: 14 },
        ],
        rows: customers.map((c) => ({ ...c, phone: phoneText(c.phone), oldestText: c.oldest ? dateLabel(ymdOf(new Date(c.oldest))) : '' })),
      },
      {
        title: 'Unpaid orders',
        columns: [
          { header: 'Order', key: 'id', width: 8 },
          { header: 'Date', key: 'dateText', width: 14 },
          { header: 'Customer', key: 'name', width: 26 },
          { header: 'Gallons', key: 'quantity', width: 9, kind: 'num' },
          { header: 'Type', key: 'order_type', width: 10 },
          { header: 'Amount', key: 'total', width: 13, kind: 'money' },
        ],
        rows: orders.map((o) => ({
          ...o,
          id: `#${o.order_id}`,
          dateText: dateLabel(ymdOf(new Date(o.at))),
          name: nameOf[o.ckey] || 'Walk-in',
          total: Number(o.total_amount),
        })),
      },
    ],
  };
}

/** PDF as a Buffer. */
function toPdf(r) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 40, info: { Title: `${r.title} - ${r.subtitle}`, Author: STATION } });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    const left = doc.page.margins.left;
    const width = doc.page.width - left - doc.page.margins.right;

    // Header
    if (fs.existsSync(LOGO)) doc.image(LOGO, left, 36, { width: 44 });
    doc.fillColor('#111827').font('Helvetica-Bold').fontSize(16).text(STATION, left + 54, 40);
    doc.font('Helvetica').fontSize(10).fillColor('#6B7280').text(`Created ${dateLabel(ymdOf(now()))} ${clockOf(now())}`, left + 54, 60);
    doc.moveTo(left, 90).lineTo(left + width, 90).lineWidth(1.5).strokeColor(BLUE).stroke();
    doc.fillColor(BLUE).font('Helvetica-Bold').fontSize(18).text(r.title, left, 102);
    doc.fillColor('#111827').font('Helvetica').fontSize(11).text(r.subtitle, left, 124);

    // Summary, two columns
    let y = 150;
    const colW = width / 2;
    r.summary.forEach(([label, value, kind], i) => {
      const x = left + (i % 2) * colW;
      if (i % 2 === 0 && i > 0) y += 22;
      doc.font('Helvetica').fontSize(10).fillColor('#6B7280').text(label, x, y, { width: colW * 0.55 });
      doc.font('Helvetica-Bold').fontSize(11).fillColor('#111827').text(kind === 'money' ? money(value) : String(value), x + colW * 0.55, y, { width: colW * 0.4 });
    });
    y += 34;

    // Tables
    for (const t of r.tables) {
      if (y > doc.page.height - 120) {
        doc.addPage();
        y = 40;
      }
      doc.font('Helvetica-Bold').fontSize(12).fillColor('#111827').text(t.title, left, y);
      y += 18;
      const total = t.columns.reduce((a, c) => a + c.width, 0);
      const widths = t.columns.map((c) => (c.width / total) * width);
      const header = () => {
        doc.rect(left, y, width, 18).fill(BLUE);
        let x = left;
        t.columns.forEach((c, i) => {
          doc.font('Helvetica-Bold').fontSize(9).fillColor('#FFFFFF').text(c.header, x + 4, y + 5, { width: widths[i] - 8, align: c.kind ? 'right' : 'left' });
          x += widths[i];
        });
        y += 18;
      };
      header();
      if (!t.rows.length) {
        doc.font('Helvetica').fontSize(9).fillColor('#6B7280').text('None', left + 4, y + 5);
        y += 20;
      }
      t.rows.forEach((row, n) => {
        if (y > doc.page.height - 60) {
          doc.addPage();
          y = 40;
          header();
        }
        if (n % 2 === 1) doc.rect(left, y, width, 17).fill('#EEF6FD');
        let x = left;
        t.columns.forEach((c, i) => {
          const v = row[c.key];
          doc.font('Helvetica').fontSize(9).fillColor('#111827')
            .text(c.kind === 'money' ? money(v) : v === null || v === undefined ? '' : String(v), x + 4, y + 4, {
              width: widths[i] - 8,
              align: c.kind ? 'right' : 'left',
              lineBreak: false,
              ellipsis: true,
            });
          x += widths[i];
        });
        y += 17;
      });
      y += 18;
    }
    doc.end();
  });
}

/** Spreadsheet (.xlsx) as a Buffer: a Summary sheet and one sheet per table. */
async function toXlsx(r) {
  const wb = new ExcelJS.Workbook();
  wb.creator = STATION;
  wb.created = now();
  const head = { font: { bold: true, color: { argb: 'FFFFFFFF' } }, fill: { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0A84E0' } } };
  const PESO = '"₱"#,##0.00';

  const s = wb.addWorksheet('Summary');
  s.columns = [{ width: 28 }, { width: 22 }];
  s.addRow([STATION]).font = { bold: true, size: 14 };
  s.addRow([r.title]).font = { bold: true, size: 12, color: { argb: 'FF0A84E0' } };
  s.addRow([r.subtitle]);
  s.addRow([]);
  for (const [label, value, kind] of r.summary) {
    const row = s.addRow([label, value]);
    if (kind === 'money') row.getCell(2).numFmt = PESO;
    row.getCell(2).font = { bold: true };
  }

  for (const t of r.tables) {
    const ws = wb.addWorksheet(t.title.slice(0, 31));
    ws.columns = t.columns.map((c) => ({ header: c.header, key: c.key, width: Math.max(c.width + 4, c.header.length + 2) }));
    const h = ws.getRow(1);
    h.eachCell((cell) => Object.assign(cell, head));
    t.rows.forEach((row) => ws.addRow(Object.fromEntries(t.columns.map((c) => [c.key, c.kind === 'money' ? Number(row[c.key] || 0) : row[c.key] ?? '']))));
    t.columns.forEach((c, i) => {
      if (c.kind === 'money') ws.getColumn(i + 1).numFmt = PESO;
    });
    ws.views = [{ state: 'frozen', ySplit: 1 }];
  }
  return Buffer.from(await wb.xlsx.writeBuffer());
}

async function exportFile(report, date, format) {
  const r = await buildReport(report, date);
  const buf = format === 'pdf' ? await toPdf(r) : await toXlsx(r);
  return {
    fileName: `${r.fileBase}.${format === 'pdf' ? 'pdf' : 'xlsx'}`,
    type: format === 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    buf,
  };
}

module.exports = { buildReport, exportFile };
