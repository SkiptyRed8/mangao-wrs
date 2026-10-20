// Builds Mangao-Team-Testing-Guide.docx (phone testing guide for teammates) from team-cases.js.
// Run: node build-team.js
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  HeadingLevel, AlignmentType, PageNumber, Footer, Header, TableLayoutType, ExternalHyperlink,
} = require('docx');
const parts = require('./team-cases');

const BLUE = '0A84E0';
const LIGHT = 'EAF4FD';
const INK = '15202B';
const MUTED = '64707C';
const FONT = 'Arial';
const W = 10466; // A4 width minus 0.5 inch margins (DXA)
const APK = 'https://github.com/SkiptyRed8/mangao-wrs/releases/tag/app-latest';

const peso = (s) => s.replace(/\bP(\d)/g, '₱$1');
const run = (text, o = {}) => new TextRun({ text: peso(text), font: FONT, size: o.size || 20, bold: o.bold, color: o.color || INK, italics: o.italics });
const para = (text, o = {}) =>
  new Paragraph({ children: Array.isArray(text) ? text : [run(text, o)], spacing: { after: o.after ?? 80, before: o.before ?? 0 }, alignment: o.align });
const h1 = (text, o = {}) =>
  new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: o.page, children: [run(text, { size: 30, bold: true, color: BLUE })], spacing: { before: o.page ? 0 : 240, after: 100 } });

const border = { style: BorderStyle.SINGLE, size: 4, color: 'B9D7F2' };
const borders = { top: border, bottom: border, left: border, right: border };

function cell(children, width, o = {}) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    shading: o.fill ? { type: ShadingType.CLEAR, color: 'auto', fill: o.fill } : undefined,
    margins: { top: 70, bottom: 70, left: 100, right: 100 },
    children: (Array.isArray(children) ? children : [children]).map((c) => (typeof c === 'string' ? para(c, { after: 0, size: o.size || 19, bold: o.bold }) : c)),
  });
}

function table(widths, header, rows, o = {}) {
  return new Table({
    width: { size: W, type: WidthType.DXA },
    columnWidths: widths,
    layout: TableLayoutType.FIXED,
    rows: [
      new TableRow({
        tableHeader: true,
        children: header.map((h, i) => cell(para([run(h, { bold: true, color: 'FFFFFF', size: 19 })], { after: 0 }), widths[i], { fill: BLUE })),
      }),
      ...rows.map(
        (r, ri) =>
          new TableRow({
            cantSplit: true,
            children: r.map((c, i) => cell(c, widths[i], { fill: ri % 2 ? LIGHT : undefined, bold: o.boldFirst && i === 0 })),
          })
      ),
    ],
  });
}

const total = parts.reduce((n, p) => n + p.cases.length, 0);
const children = [
  new Paragraph({ children: [run('Mangao WRS – Team Testing Guide', { size: 44, bold: true, color: BLUE })], spacing: { after: 40 } }),
  para('Testing the system on Android phones (online server)', { size: 24, color: MUTED, after: 200 }),

  h1('1. Install the app (5 minutes)'),
  para([run('1. On your Android phone, open this link in Chrome: ', {}), new ExternalHyperlink({ link: APK, children: [new TextRun({ text: APK, font: FONT, size: 20, color: BLUE, underline: {} })] })]),
  para('    (or install the mangao-wrs.apk file Amalyn sends you).'),
  para('2. Under "Assets", tap mangao-wrs.apk. If Chrome warns, tap "Download anyway".'),
  para('3. Open the downloaded file. Allow installing from Chrome (Settings > "Allow from this source"), go back, tap Install.'),
  para('4. If Play Protect warns "unknown developer": tap "More details" > "Install anyway". (It warns only because the app is not from the Play Store.)'),
  para('5. Open "Mangao WRS". The first time it can take up to 1 minute while the online server wakes up.'),
  para('6. Check the version under the buttons on the Welcome screen (also at the bottom of My Account). It must match the newest version on the GitHub page (e.g. "version 1.0.13"). If it is older, install the new APK again; in the web version close the tab and open the link again.'),
  para('You need internet on the phone (Wi-Fi or mobile data). Allow location and camera when the app asks.', { color: MUTED }),
  para('Testing indoors? The owner can turn on More > Prices & Settings > Demo ride: the sidecar then drives from the station to the customer by itself. Turn it off afterwards.', { color: MUTED }),

  h1('2. Accounts to log in with'),
  table(
    [1900, 2700, 2500, 3366],
    ['Role', 'Name', 'Phone number', 'Password'],
    [
      ['Owner', 'Ervin P. Mangao', '09170000001', 'Ask Amalyn'],
      ['Staff', 'Joy Ramos', '09170000002', 'staff123'],
      ['Rider', 'Juan Dela Cruz', '09170000003', 'rider123'],
      ['Customer', 'Ana Lim', '09172001111', 'ana123'],
      ['Customer', 'Maria Santos', '09171234567', 'maria123'],
      ['Customer', 'Pedro Reyes', '09172221010', 'pedro123'],
      ['Customer', 'Your own', 'Tap Sign up', 'Your own'],
    ],
    { boldFirst: true }
  ),
  para('Type the phone number with or without spaces (0917 000 0002 also works).', { color: MUTED, before: 60 }),

  h1('3. Rules while testing'),
  para('• Everyone uses the SAME online system: an order you place shows up on the other testers\' phones. That is expected.'),
  para('• Do not change the owner password or edit/deactivate the demo accounts. If you change a price or the tank limit, put it back.'),
  para('• Do not pull down to refresh when a check says "by itself": the screen should change within a few seconds on its own.'),
  para('• For every check, tick Pass or Fail. For a Fail: take a screenshot and write the check number (e.g. "B6") and what happened.'),
  para('• Send all Fails to Amalyn in the group chat (screenshot + check number).'),

  h1('4. Who does what'),
  para(`${parts.length} parts, ${total} checks. With 4 testers, each takes one role (Parts A to D). Suggested order: everyone logs in first, do Part E together (it needs all four phones), then continue your own part. With fewer testers, one person can do two roles on two phones, or log out and log in as the other role.`),
  table(
    [1000, 3700, 2700, 1500, 1566],
    ['Part', 'Role', 'Who', 'Checks', 'Tester name'],
    parts.map((p) => [p.id, p.title, p.who, String(p.cases.length), ''])
  ),
];

for (const p of parts) {
  children.push(
    h1(`Part ${p.id} · ${p.title}`, { page: true }),
    para([run('Who: ', { bold: true }), run(p.who)], { after: 40 }),
    para([run('Log in as: ', { bold: true }), run(p.login)], { after: p.intro ? 40 : 100 }),
  );
  if (p.intro) children.push(para([run('Note: ', { bold: true, color: BLUE }), run(p.intro)], { after: 100 }));
  children.push(
    table(
      [700, 3900, 3900, 900, 1066],
      ['#', 'Do this', 'You should see', 'Result', 'Notes'],
      p.cases.map((c, i) => [`${p.id}${i + 1}`, c[0], c[1], [para('☐ Pass', { after: 0, size: 18 }), para('☐ Fail', { after: 0, size: 18 })], ''])
    )
  );
}

children.push(
  h1('Problems found', { page: true }),
  para('Write each Fail here (or send it in the group chat with a screenshot).'),
  table(
    [900, 1800, 5266, 1300, 1200],
    ['Check', 'Tester', 'What happened', 'Phone model', 'Screenshot sent?'],
    Array.from({ length: 12 }, () => ['', '', '', '', '☐'])
  )
);

const doc = new Document({
  creator: 'Mangao WRS project team',
  title: 'Mangao WRS Team Testing Guide',
  styles: { default: { document: { run: { font: FONT, size: 20 } } } },
  sections: [
    {
      properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 720, bottom: 720, left: 720, right: 720 } } },
      headers: { default: new Header({ children: [para('Mangao Water Refilling Station – Team Testing Guide (Android)', { color: MUTED, size: 16, align: AlignmentType.RIGHT })] }) },
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

const out = path.join(__dirname, 'Mangao-Team-Testing-Guide.docx');
Packer.toBuffer(doc).then((b) => {
  fs.writeFileSync(out, b);
  console.log(`Wrote ${out} (${parts.length} parts, ${total} checks)`);
});
