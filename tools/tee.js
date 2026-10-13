// Shows a program's output in its window and also saves it to a log file (for troubleshooting).
// Usage: some-command 2>&1 | node tee.js path\to\file.log
const fs = require('fs');
const out = fs.createWriteStream(process.argv[2], { flags: 'w' });
process.stdin.on('data', (chunk) => {
  process.stdout.write(chunk);
  out.write(chunk);
});
process.stdin.on('end', () => out.end());
