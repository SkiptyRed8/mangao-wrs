// Builds Mangao-Testing-Checklist.docx from cases.js.  Run: node build.js
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  HeadingLevel, AlignmentType, PageNumber, Footer, Header, TableLayoutType,
} = require('docx');
const steps = require('./cases');

const BLUE = '0A84E0';
const LIGHT = 'EAF4FD';
const INK = '15202B';
const MUTED = '64707C';
const FONT = 'Arial';
const W = 10466; // A4 width minus 0.5 inch margins (DXA)

const peso = (s) => s.replace(/\bP(\d)/g, '₱$1');
const run = (text, o = {}) => new TextRun({ text: peso(text), font: FONT, size: o.size || 19, bold: o.bold, color: o.color || INK, italics: o.italics });
const para = (text, o = {}) =>
  new Paragraph({ children: Array.isArray(text) ? text : [run(text, o)], spacing: { after: o.after ?? 80, before: o.before ?? 0 }, alignment: o.align });

const border = { style: BorderStyle.SINGLE, size: 4, color: 'B9D7F2' };
const borders = { top: border, bottom: border, left: border, right: border };

function cell(children, width, o = {}) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    shading: o.fill ? { type: ShadingType.CLEAR, color: 'auto', fill: o.fill } : undefined,
    margins: { top: 60, bottom: 60, left: 90, right: 90 },
    children: (Array.isArray(children) ? children : [children]).map((c) => (typeof c === 'string' ? para(c, { after: 0, ...o }) : c)),
  });
}

function table(widths, header, rows) {
  return new Table({
    width: { size: W, type: WidthType.DXA },
    columnWidths: widths,
    layout: TableLayoutType.FIXED,
    rows: [
      new TableRow({
        tableHeader: true,
        children: header.map((h, i) => cell(para([run(h, { bold: true, color: 'FFFFFF', size: 18 })], { after: 0 }), widths[i], { fill: BLUE })),
      }),
      ...rows.map(
        (r, ri) =>
          new TableRow({
            cantSplit: true,
            children: r.map((c, i) => cell(c, widths[i], { fill: ri % 2 ? LIGHT : undefined, size: 18 })),
          })
      ),
    ],
  });
}

function phNow() {
  const d = new Date(Date.now() + 8 * 3600 * 1000);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const h = d.getUTCHours();
  return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}, ${h % 12 || 12}:${String(d.getUTCMinutes()).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

const total = steps.reduce((n, s) => n + s.cases.length, 0);
const CASE_W = [640, 3820, 3900, 900, 1206];
const children = [
  new Paragraph({ heading: HeadingLevel.TITLE, children: [run('Mangao WRS – Testing Checklist', { size: 40, bold: true, color: BLUE })], spacing: { after: 60 } }),
  para(`Steps built but not yet checked in Chrome: ${steps.length} steps, ${total} checks. Updated ${phNow()}.`, { color: MUTED }),

  new Paragraph({ heading: HeadingLevel.HEADING_1, children: [run('Before you start', { size: 28, bold: true, color: BLUE })], spacing: { before: 200, after: 80 } }),
  para('1. Close the two black Mangao windows (server and app) if they are open.'),
  para('2. Double-click RESET-DEMO-DATA.bat and type Y. This puts back the demo accounts and demo orders (it erases what you typed while testing).'),
  para('3. Double-click START.bat and wait for Chrome to open the app.'),
  para('4. For checks with two people (owner and customer), open a second Chrome window in Incognito (Ctrl+Shift+N) at the same address: one window per account.'),
  para('5. Tick Pass or Fail for each check. For a Fail, write what happened in Notes and send a screenshot.'),

  new Paragraph({ heading: HeadingLevel.HEADING_2, children: [run('Demo accounts', { size: 24, bold: true, color: INK })], spacing: { before: 160, after: 80 } }),
  table(
    [2400, 2600, 2400, 3066],
    ['Role', 'Name', 'Phone', 'Password'],
    [
      ['Owner', 'Ervin P. Mangao', '0917 000 0001', 'owner123'],
      ['Staff', 'Joy Ramos', '0917 000 0002', 'staff123'],
      ['Rider', 'Juan Dela Cruz', '0917 000 0003', 'rider123'],
      ['Customer', 'Ana Lim', '0917 200 1111', 'ana123'],
      ['Customer', 'Maria Santos', '0917 123 4567', 'maria123'],
      ['Customer', 'Pedro Reyes', '0917 222 1010', 'pedro123'],
    ]
  ),

  new Paragraph({ heading: HeadingLevel.HEADING_2, children: [run('Summary', { size: 24, bold: true, color: INK })], spacing: { before: 200, after: 80 } }),
  table(
    [900, 4400, 2600, 1300, 1266],
    ['Step', 'What', 'Screens', 'Checks', 'All passed?'],
    steps.map((s) => [String(s.n), s.title, s.screens, String(s.cases.length), '☐ Yes  ☐ No'])
  ),
];

for (const s of steps) {
  children.push(
    new Paragraph({
      heading: HeadingLevel.HEADING_1,
      pageBreakBefore: true,
      children: [run(`Step ${s.n} · ${s.title}`, { size: 28, bold: true, color: BLUE })],
      spacing: { after: 60 },
    }),
    para([run('Screens: ', { bold: true }), run(s.screens), run('    Log in as: ', { bold: true }), run(s.as)], { after: 60 }),
  );
  if (s.before) children.push(para([run('Before: ', { bold: true, color: BLUE }), run(s.before)], { after: 60 }));
  children.push(
    table(
      CASE_W,
      ['#', 'What to do', 'What you should see', 'Result', 'Notes'],
      s.cases.map((c, i) => [`${s.n}.${i + 1}`, c[0], c[1], '☐ Pass\n☐ Fail', ''].map((v) => (v.includes('\n') ? v.split('\n').map((x) => para(x, { after: 0, size: 18 })) : v)))
    )
  );
}

const doc = new Document({
  creator: 'Mangao WRS project team',
  title: 'Mangao WRS Testing Checklist',
  styles: { default: { document: { run: { font: FONT, size: 19 } } } },
  sections: [
    {
      properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 720, bottom: 720, left: 720, right: 720 } } },
      headers: { default: new Header({ children: [para('Mangao Water Refilling Station – Order, Inventory, Sales & Delivery Management System', { color: MUTED, size: 16, align: AlignmentType.RIGHT })] }) },
      footers: {
        default: new Footer({
          children: [
            new Paragraph({
              alignment: AlignmentType.CENTER,
              children: [new TextRun({ font: FONT, size: 16, color: MUTED, children: ['Page ', PageNumber.CURRENT, ' of ', PageNumber.TOTAL_PAGES] })],
            }),
          ],
        }),
      },
      children,
    },
  ],
});

const out = path.join(__dirname, 'Mangao-Testing-Checklist.docx');
Packer.toBuffer(doc).then((b) => {
  fs.writeFileSync(out, b);
  console.log(`Wrote ${out} (${steps.length} steps, ${total} checks)`);
});
