// Checks the Gmail settings in server/.env and sends one test email to SMTP_USER.
// Run: npm run mail:test   (or double-click TEST-EMAIL.bat)
const config = require('../src/config');
const { getTransport, mailHint } = require('../src/services/mail');

(async () => {
  const m = config.mail;
  console.log('');
  if (!m.user || !m.pass) {
    console.log('SMTP_USER or SMTP_PASS is empty in server\\.env. Fill both, save, and run this again.');
    process.exit(1);
  }
  const problems = [];
  if (!/^[^\s@]+@gmail\.com$/i.test(m.user)) problems.push('SMTP_USER should be the full Gmail address, e.g. yourname@gmail.com');
  if (m.pass.length !== 16) problems.push(`SMTP_PASS has ${m.pass.length} letters; a Google App Password has 16 (spaces do not matter)`);
  if (!/^[a-z]+$/i.test(m.pass)) problems.push('SMTP_PASS has numbers or symbols; an App Password is letters only. Did you type your normal Gmail password?');
  console.log(`Gmail account : ${m.user}`);
  console.log(`App Password  : ${m.pass.length} letters`);
  console.log(`Server        : ${m.host}:${m.port}`);
  for (const p of problems) console.log(`  ! ${p}`);
  console.log('\nLogging in to Gmail...');
  try {
    const t = getTransport();
    await t.verify();
    console.log('Login OK. Sending a test email to ' + m.user + ' ...');
    await t.sendMail({ from: config.mail.from, to: m.user, subject: 'Mangao WRS test email', text: 'Email works. Forgot password codes will arrive like this.' });
    console.log('\nDONE: test email sent. Check the inbox (or Spam) of ' + m.user + '.');
    process.exit(0);
  } catch (err) {
    console.log('\nFAILED: ' + err.message.split('\n')[0]);
    console.log('What to do: ' + mailHint(err));
    process.exit(1);
  }
})();
