const { exec } = require('child_process');

if (process.argv.length < 3) {
  console.error('Please provide a chain input as an argument.');
  process.exit(1);
}

const command = process.argv[2];
const extraArgs = process.argv.slice(3).join(' ');

exec(`bun run lib/utils/utils/${command}.js ${extraArgs}`, (error, stdout, stderr) => {
  if (error) {
    console.log(error);
    process.exit(1);
  }
  if (stderr) {
    console.log(stderr);
    process.exit(1);
  }
  console.log(stdout);
});
