// Checks the Gmail settings in server\.env without using the app:  npm run mail:test
// Optional: npm run mail:test -- someone@gmail.com   (also sends a test email there)
const config = require('../src/config');
const { mailReady, getTransport, mailHint } = require('../src/services/mail');

(async () => {
  console.log(`SMTP_USER : ${config.mail.user || '(empty)'}`);
  console.log(`SMTP_PASS : ${config.mail.pass ? `${config.mail.pass.length} characters` : '(empty)'}  (an App Password has 16)`);
  console.log(`Server    : ${config.mail.host}:${config.mail.port}`);
  if (!mailReady()) {
    console.log('\nSMTP_USER or SMTP_PASS is empty in server\\.env, so email is OFF.');
    process.exit(1);
  }
  try {
    await getTransport().verify();
    console.log('\nOK: Gmail accepted the login.');
    const to = process.argv[2];
    if (to) {
      await getTransport().sendMail({ from: config.mail.from, to, subject: 'Mangao test email', text: 'Email from the Mangao system works.' });
      console.log(`Test email sent to ${to}. Check the inbox (and Spam).`);
    }
  } catch (err) {
    console.log(`\nFAILED: ${err.message}\n${mailHint(err)}`);
    process.exit(1);
  }
})();
