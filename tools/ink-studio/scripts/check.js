// node scripts/check.js : the comment guard over the library's own sources
const lib = require('..'),
  bad = lib.lint(lib.files().concat(lib.demoFiles()));
if (bad.length) {
  console.error('code after a // comment on the same line (it would never run):\n  ' + bad.join('\n  '));
  process.exit(1);
}
console.log('clean');
