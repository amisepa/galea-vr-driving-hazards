/* Turn manuscript/osf_update_DRAFT.md into a Word document.
 *
 * The markdown is fine for version control but painful to paste from. This
 * renders the same content as OSF_Update.docx, with the paste-ready text in
 * shaded blocks so it is obvious what goes into the OSF form and what is an
 * instruction to you.
 *
 * Usage:  node build_osf_update.js
 */

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, AlignmentType, HeadingLevel,
  Footer, PageNumber, convertInchesToTwip, BorderStyle, ShadingType,
} = require('docx');

const ROOT = 'C:\\Users\\ccann\\Documents\\MATLAB\\galea';
const SRC = path.join(ROOT, 'manuscript', 'osf_update_DRAFT.md');
const OUT = path.join(ROOT, 'manuscript', 'OSF_Update.docx');

const FONT = 'Calibri';
const SZ = 22;        // 11 pt
const INK = '1F2933';
const QUOTE_BG = 'F2F4F7';

/* Inline markdown -> TextRuns: **bold**, *italic*, `code`. */
function runs(text, base = {}) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/g;
  let last = 0, m;
  const push = (t, extra) => {
    if (t) out.push(new TextRun({ text: t, font: base.font || FONT, size: base.size || SZ, color: INK, ...base.run, ...extra }));
  };
  while ((m = re.exec(text)) !== null) {
    push(text.slice(last, m.index));
    const tok = m[0];
    if (tok.startsWith('**')) push(tok.slice(2, -2), { bold: true });
    else if (tok.startsWith('`')) push(tok.slice(1, -1), { font: 'Consolas', size: SZ - 2 });
    else push(tok.slice(1, -1), { italics: true });
    last = m.index + tok.length;
  }
  push(text.slice(last));
  return out;
}

const md = fs.readFileSync(SRC, 'utf8').split(/\r?\n/);
const children = [];

/* Group consecutive lines into blocks so wrapped markdown becomes one
 * paragraph rather than one paragraph per source line. */
let buf = [], mode = null;

function flush() {
  if (!buf.length) return;
  const text = buf.join(' ').replace(/\s+/g, ' ').trim();
  if (text) {
    if (mode === 'quote') {
      children.push(new Paragraph({
        spacing: { before: 60, after: 60, line: 280 },
        indent: { left: 360, right: 360 },
        shading: { type: ShadingType.CLEAR, fill: QUOTE_BG, color: 'auto' },
        border: { left: { style: BorderStyle.SINGLE, size: 12, color: '9AA5B1', space: 8 } },
        children: runs(text),
      }));
    } else if (mode === 'quotebullet' || mode === 'bullet') {
      children.push(new Paragraph({
        bullet: { level: 0 },
        spacing: { before: 40, after: 40, line: 280 },
        indent: { left: mode === 'quotebullet' ? 720 : 460 },
        shading: mode === 'quotebullet'
          ? { type: ShadingType.CLEAR, fill: QUOTE_BG, color: 'auto' } : undefined,
        children: runs(text),
      }));
    } else {
      children.push(new Paragraph({
        spacing: { before: 80, after: 120, line: 300 },
        children: runs(text),
      }));
    }
  }
  buf = []; mode = null;
}

for (const raw of md) {
  const line = raw.replace(/\s+$/, '');

  if (/^\s*$/.test(line)) { flush(); continue; }

  if (/^---+$/.test(line)) { flush(); continue; }           // rules add nothing here

  let m;
  if ((m = line.match(/^(#{1,3})\s+(.*)$/))) {
    flush();
    const level = m[1].length;
    children.push(new Paragraph({
      spacing: { before: level === 1 ? 0 : 280, after: 140 },
      heading: level === 1 ? HeadingLevel.TITLE
        : level === 2 ? HeadingLevel.HEADING_1 : HeadingLevel.HEADING_2,
      children: runs(m[2], { size: level === 1 ? 34 : level === 2 ? 28 : 24, run: { bold: true } }),
    }));
    continue;
  }

  if ((m = line.match(/^>\s?-\s+(.*)$/))) {                  // bullet inside a quote
    flush();                                                 // each dash starts a new bullet
    mode = 'quotebullet'; buf.push(m[1]); continue;
  }
  if ((m = line.match(/^>\s?(\d+\.)\s+(.*)$/))) {            // numbered item inside a quote
    flush();                                                 // each number starts a new paragraph
    // Keep the literal "1." so the numbering survives being pasted into a
    // plain-text OSF field, which is what this document is for.
    mode = 'quote'; buf.push(m[1] + ' ' + m[2]); continue;
  }
  if ((m = line.match(/^>\s?(.*)$/))) {                      // quote body or continuation
    const body = m[1];
    if (!body.trim()) { flush(); continue; }
    // An indented line under a bullet or a numbered item is that item wrapping,
    // not a new block.
    if ((mode === 'quotebullet' || mode === 'quote') && /^\s/.test(body)) {
      buf.push(body.trim()); continue;
    }
    if (mode !== 'quote') flush();
    mode = 'quote'; buf.push(body.trim()); continue;
  }
  if ((m = line.match(/^-\s+(.*)$/))) {                       // plain bullet
    flush();
    mode = 'bullet'; buf.push(m[1]); continue;
  }
  if (mode === 'bullet' && /^\s+\S/.test(line)) {             // wrapped plain bullet
    buf.push(line.trim()); continue;
  }

  if (mode === 'quote' || mode === 'quotebullet' || mode === 'bullet') {
    buf.push(line.trim()); continue;                          // wrapped continuation
  }
  if (mode !== 'para') flush();
  mode = 'para'; buf.push(line.trim());
}
flush();

const doc = new Document({
  styles: { default: { document: { run: { font: FONT, size: SZ, color: INK } } } },
  sections: [{
    properties: {
      page: {
        margin: {
          top: convertInchesToTwip(1), bottom: convertInchesToTwip(1),
          left: convertInchesToTwip(1), right: convertInchesToTwip(1),
        },
      },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 18, color: '7B8794' })],
        })],
      }),
    },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(OUT, buf);
  console.log('Wrote ' + OUT);
  console.log(`  ${children.length} blocks from ${path.basename(SRC)}`);
});
