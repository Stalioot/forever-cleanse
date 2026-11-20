// node tools/logo.js → media/logo-400.png (GitHub, CurseForge) and addon/ForeverCleanse/Media/logo.tga (64x64, in game)
// Crops the chosen icon out of media/logo-sheet.png (the generated 3x2 sheet) with Edge headless (Windows),
// then turns the small PNG into a 32-bit TGA the game can load.
const fs = require('fs'), path = require('path'), zlib = require('zlib'), os = require('os'), { execFileSync } = require('child_process');
const root = path.join(__dirname, '..');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const SHEET = path.join(root, 'media/logo-sheet.png');
const CROP = { x: 16, y: 530, size: 480 }; // bottom row, left: the cut skull

function shoot(size, out) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fclogo-'));
  const html = path.join(tmp, 'logo.html');
  const k = size / CROP.size, src = 'file:///' + SHEET.replace(/\\/g, '/');
  fs.writeFileSync(html, `<!doctype html><html><body style="margin:0;background:#000;overflow:hidden"><div style="width:${size}px;height:${size}px;overflow:hidden;position:relative"><img src="${src}" style="position:absolute;left:${-CROP.x * k}px;top:${-CROP.y * k}px;width:${1536 * k}px;height:${1024 * k}px"></div></body></html>`);
  execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--user-data-dir=${tmp}`, '--default-background-color=00000000',
    `--window-size=${size},${size}`, `--screenshot=${out}`, 'file:///' + html.replace(/\\/g, '/')], { stdio: 'ignore' });
}

// minimal PNG reader: 8-bit RGBA (colour type 6) or RGB (2), not interlaced
function readPng(file) {
  const b = fs.readFileSync(file);
  let p = 8, w, h, type, idat = [];
  while (p < b.length) {
    const len = b.readUInt32BE(p), t = b.toString('ascii', p + 4, p + 8), d = b.subarray(p + 8, p + 8 + len);
    if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); type = d[9]; if (d[8] !== 8 || d[12]) throw new Error('unsupported PNG') }
    if (t === 'IDAT') idat.push(d);
    p += 12 + len;
  }
  const bpp = type === 6 ? 4 : 3, raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * bpp, px = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)], line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0, up = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      const pr = a + up - c, pa = Math.abs(pr - a), pb = Math.abs(pr - up), pc = Math.abs(pr - c);
      line[i] = (line[i] + [0, a, up, (a + up) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? up : c][f]) & 255;
    }
    for (let x = 0; x < w; x++) for (let k = 0; k < 4; k++) px[(y * w + x) * 4 + k] = k < bpp ? line[x * bpp + k] : 255;
    prev = line;
  }
  return { w, h, px };
}

function writeTga(file, { w, h, px }) {
  const head = Buffer.alloc(18);
  head[2] = 2; head.writeUInt16LE(w, 12); head.writeUInt16LE(h, 14); head[16] = 32; head[17] = 8 | 32; // top-left origin, 8 alpha bits
  const body = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) { body[i * 4] = px[i * 4 + 2]; body[i * 4 + 1] = px[i * 4 + 1]; body[i * 4 + 2] = px[i * 4]; body[i * 4 + 3] = px[i * 4 + 3] }
  fs.writeFileSync(file, Buffer.concat([head, body]));
}

shoot(400, path.join(root, 'media/logo-400.png'));
// banner and Ko-fi button for README and CurseForge: media/<name>.html → media/<name>.png, transparent corners, waits for the web font
for (const [name, w, h] of [['banner', 600, 160], ['kofi', 210, 160]]) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fcpage-'));
  execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--user-data-dir=${tmp}`, '--default-background-color=00000000',
    '--virtual-time-budget=8000', `--window-size=${w},${h}`, `--screenshot=${path.join(root, 'media', name + '.png')}`,
    'file:///' + path.join(root, 'media', name + '.html').replace(/\\/g, '/')], { stdio: 'ignore' });
}
const small = path.join(os.tmpdir(), 'fclogo-64.png');
shoot(64, small);
fs.mkdirSync(path.join(root, 'addon/ForeverCleanse/Media'), { recursive: true });
const img = readPng(small);
writeTga(path.join(root, 'addon/ForeverCleanse/Media/logo.tga'), img);
console.log('logo-400.png and Media/logo.tga (' + img.w + 'x' + img.h + ')');
