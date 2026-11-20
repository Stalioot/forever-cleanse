// node tools/gallery.js → media/slide-1..6.png (1280x720): the CurseForge and GitHub gallery, from media/gallery.html
// The slides frame the in-game screenshots media/shot-*.png. Edge headless, as tools/logo.js.
const fs = require('fs'), path = require('path'), os = require('os'), { execFileSync } = require('child_process');
const root = path.join(__dirname, '..');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const page = 'file:///' + path.join(root, 'media/gallery.html').split(path.sep).join('/');
for (let n = 1; n <= 6; n++) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fcslide-'));
  execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--user-data-dir=${tmp}`, '--allow-file-access-from-files',
    '--virtual-time-budget=8000', '--window-size=1280,720', `--screenshot=${path.join(root, 'media', `slide-${n}.png`)}`, `${page}#${n}`], { stdio: 'ignore' });
}
console.log('media/slide-1..6.png');
