import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const work = dirname(fileURLToPath(import.meta.url));
const delivery = resolve(work, '../..');
const brand = dirname(delivery);
const skillScripts = process.env.APP_ICON_SKILL_SCRIPTS || 'C:/Users/NiMo/.agents/skills/app-icon-gen/scripts';
const require = createRequire(join(skillScripts, 'package.json'));
const { Resvg } = require('@resvg/resvg-js');

const palette = {
  blue: '#0065D4', blueTop: '#2385F5', blueBottom: '#0756CC',
  light: '#F5F5F7', dark: '#09090B', ink: '#17191F',
  muted: '#666B75', darkMuted: '#969BA5', darkBlue: '#70ADFF', white: '#FFFFFF',
};

// Three rising audio bars. The tallest turns into the final line of a transcript.
// All geometry is authored as positive filled forms, with no outlined strokes.
const signal = '<rect x="244" y="438" width="80" height="148" rx="40"/>'
  + '<rect x="380" y="350" width="80" height="324" rx="40"/>';
const transcript = '<path d="M556 278C578.091 278 596 295.909 596 318V666H748C770.091 666 788 683.909 788 706C788 728.091 770.091 746 748 746H556C533.909 746 516 728.091 516 706V318C516 295.909 533.909 278 556 278Z"/>'
  + '<rect x="652" y="278" width="136" height="80" rx="40"/>'
  + '<rect x="652" y="472" width="136" height="80" rx="40"/>';
const mark = (fill) => `<g fill="${fill}">${signal}${transcript}</g>`;
const frame = (w, h, body, defs = '', label = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img"${label ? ` aria-label="${label}"` : ''}><defs>${defs}</defs>${body}</svg>`;
const gradient = '<linearGradient id="brand-blue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2385F5"/><stop offset="1" stop-color="#0756CC"/></linearGradient>';
const font = 'Segoe UI';
const text = (x, y, size, fill, content, extras = '') => `<text x="${x}" y="${y}" font-family="${font}, sans-serif" font-size="${size}" fill="${fill}" ${extras}>${content}</text>`;

async function saveSVG(stem, svg, scale = 1) {
  await mkdir(dirname(stem), { recursive: true });
  const renderer = new Resvg(svg, {
    fitTo: { mode: 'zoom', value: scale },
    font: { loadSystemFonts: true, defaultFontFamily: font },
  });
  let portableSVG = svg;
  if (svg.includes('<text')) {
    const editable = join(work, 'editable-svg');
    await mkdir(editable, { recursive: true });
    await writeFile(join(editable, `${basename(stem)}.svg`), svg + '\n');
    // Portable deliverables keep their typography even on machines without
    // Segoe UI. Editable live-text sources remain beside the design spec.
    portableSVG = renderer.toString();
  }
  await writeFile(`${stem}.svg`, portableSVG + '\n');
  // Render from the exact serialized vector so paired exports are pixel-consistent.
  const portableRenderer = new Resvg(portableSVG, {
    fitTo: { mode: 'zoom', value: scale }, font: { loadSystemFonts: false },
  });
  await writeFile(`${stem}.png`, portableRenderer.render().asPng());
}

async function prepare() {
  const design = {
    version: 'semantic-icon-design/v0.1',
    route: 'direct-authored-package',
    app_context: {
      app_name: 'LocalMinutes', category: 'private on-device meeting recorder',
      job_to_be_done: 'Turn a spoken meeting into a transcript and useful notes on the iPhone.',
      tone: 'Clear, calm, precise, trustworthy.',
    },
    style: {
      direction: 'single-hue-gradient-soft-white-symbol', svg_convertibility: 'high',
      style_notes: 'Soft white audio-to-transcript symbol on an app-aligned blue field. Direct vector authoring keeps the geometry exact and reusable.',
    },
    icon_intent: {
      metaphor: 'Spoken audio becomes written meeting minutes; the tallest signal folds into a note line.',
      small_size_readability: 'Five bold filled shapes with consistent 80-unit thickness; review at 64px and 32px.',
      must_feel_like: ['focused meeting tool', 'private', 'native to the existing app'],
      must_not_feel_like: ['generic microphone badge', 'cloud service', 'AI sparkle', 'busy document illustration'],
    },
    layering_policy: {
      negative_space_strategy: 'overlay-fill-layer', cutouts_are_layers: true,
      description: 'No cutouts are needed. Clear spacing separates positive filled signal and transcript shapes.',
    },
    canvas: {
      size: 1024, composition_anchor: 'center', alignment: 'Optically centered, with a common vertical center at 512.',
      subject_scale: { width_pct: [0.53, 0.54], height_pct: [0.45, 0.46] },
      safe_area: { x: [220, 804], y: [250, 774] },
    },
    background: {
      type: 'linear-gradient', color: palette.blue,
      gradient_stops: [palette.blueTop, palette.blueBottom],
      gradient_policy: { contrast: 'low-to-medium', hue_relationship: 'monochrome', stops: 2, rejects: ['rainbow', 'glow', 'neon', 'competing color'] },
      composer_fill_target: {
        'linear-gradient': ['extended-srgb:0.137255 0.521569 0.960784 1', 'extended-srgb:0.027451 0.337255 0.8 1'],
        orientation: { start: { x: 0.5, y: 0 }, stop: { x: 0.5, y: 1 } },
      },
    },
    layers: [
      { id: 'audio-signal', order: 1, role: 'two rising audio pulses', format_target: 'svg', shape_model: 'two filled rounded capsules', description: 'Short and medium length vertical audio strokes.', fill: '#FFFFFF', bounds: { x: [244, 460], y: [350, 674] }, geometry_constraints: ['fully opaque', 'circular ends', 'no stroke', 'no material'], must_preserve: ['80-unit thickness', '56-unit gaps'], must_not_add: ['microphone outline', 'shadow', 'glow'] },
      { id: 'written-minutes', order: 2, role: 'signal-to-note transformation', format_target: 'svg', shape_model: 'one connected L-shaped filled path and two filled capsules', description: 'Tallest pulse continues into the bottom transcript line; two shorter lines sit above.', fill: '#FFFFFF', bounds: { x: [516, 788], y: [278, 746] }, geometry_constraints: ['fully opaque', 'smooth tangent curves', 'no stroke', 'no material'], must_preserve: ['continuous lower turn', 'aligned right terminals', '80-unit thickness'], must_not_add: ['page outline', 'folded corner', 'sparkle', 'glow'] },
    ],
    conversion_constraints: { target_layer_count: '2 foreground layers plus background', svg_first: true, allowed_svg_primitives: ['filled path', 'rect'], forbidden_in_svg_assets: ['text', 'image', 'filter', 'clipPath', 'mask', 'stroke', 'shadow', 'glow'], png_fallback_allowed_only_for: [] },
    image_generation_constraints: { priority: 'Directly authored vector geometry; no bitmap concept is required.', avoid: ['existing brand marks', 'photorealism', 'bevels', 'fine detail'] },
  };
  const spec = {
    name: 'LocalMinutes', canvas: 1024, radius: 230,
    deliverable_type: 'source-package', target_platforms: ['iOS'],
    brief: 'Original LocalMinutes logo: rounded audio pulses resolve into three written lines. The blue palette extends the existing native app. This delivery contains source and preview artwork, not a compiled native icon package.',
    semantic_icon_design: design,
    semantic_review: {
      status: 'exact-enough', identity_risk: 'low', route: 'semantic-svg',
      basis: 'Original geometry authored for this app from its repository brief. No existing brand or supplied mark is being reproduced.',
      notes: 'Five filled shapes in two meaningful foreground layers; consistent 80-unit weight, centered at y=512.',
    },
    fill: design.background.composer_fill_target,
    layers: [
      { name: 'background', svg: '<rect width="1024" height="1024" fill="url(#brand-blue)"/>', defs: gradient, composer: { include: false, reason: 'Simple two-stop background belongs to the fill.' } },
      { name: 'audio-signal', svg: `<g fill="#FFFFFF">${signal}</g>`, composer: { format: 'svg', reason: 'Two clean editable audio capsules.' } },
      { name: 'written-minutes', svg: `<g fill="#FFFFFF">${transcript}</g>`, composer: { format: 'svg', reason: 'Editable transcript shapes, with the longest audio pulse connected to the bottom line.' } },
    ],
  };
  await mkdir(work, { recursive: true });
  await writeFile(join(work, 'spec.json'), JSON.stringify(spec, null, 2) + '\n');
  await writeFile(join(work, 'semantic-icon-design.json'), JSON.stringify(design, null, 2) + '\n');
  console.log('Wrote the semantic design and current icon spec.');
}

function splashBody(dark) {
  const bg = dark ? palette.dark : palette.light;
  const fg = dark ? '#F7F8FA' : palette.ink;
  const accent = dark ? palette.darkBlue : palette.blue;
  const secondary = dark ? palette.darkMuted : palette.muted;
  return `<rect width="393" height="852" fill="${bg}"/>`
    + `<svg x="142.5" y="312" width="108" height="93" viewBox="244 278 544 468">${mark(accent)}</svg>`
    + text(196.5, 459, 30, fg, 'LocalMinutes', 'text-anchor="middle" font-weight="600" letter-spacing="-0.9"')
    + text(196.5, 490, 14, secondary, 'Your meetings. Your device.', 'text-anchor="middle"')
    + text(196.5, 779, 10.5, secondary, 'RECORDED HERE. KEPT HERE.', 'text-anchor="middle" letter-spacing="1.3"');
}

function statusBar(dark) {
  const ink = dark ? '#FFFFFF' : '#15171B';
  return text(48, 38, 14, ink, '9:41', 'text-anchor="middle" font-weight="600"')
    + '<rect x="143.5" y="12" width="106" height="29" rx="14.5" fill="#050506"/>'
    + `<g fill="${ink}"><rect x="302" y="30" width="3" height="5" rx="1"/><rect x="307" y="27" width="3" height="8" rx="1"/><rect x="312" y="24" width="3" height="11" rx="1"/><rect x="317" y="21" width="3" height="14" rx="1"/><rect x="332" y="23" width="20" height="11" rx="3"/><rect x="354" y="26" width="2" height="5" rx="1"/><rect x="128" y="831" width="137" height="5" rx="2.5"/></g>`;
}

function phone(x, y, dark, id) {
  return `<g transform="translate(${x} ${y}) scale(0.89)">`
    + `<rect x="-9" y="-9" width="411" height="870" rx="59" fill="#1E2025"/>`
    + `<rect x="-7" y="-7" width="407" height="866" rx="57" fill="none" stroke="#73777F" stroke-width="1"/>`
    + `<clipPath id="screen-${id}"><rect width="393" height="852" rx="50"/></clipPath>`
    + `<g clip-path="url(#screen-${id})">${splashBody(dark)}${statusBar(dark)}</g></g>`;
}

async function exportArtwork() {
  const iconsvg = await readFile(join(delivery, 'local-minutes.preview.svg'), 'utf8');
  await mkdir(join(brand, 'logo'), { recursive: true });
  await mkdir(join(brand, 'splash'), { recursive: true });
  for (const [name, color] of [['blue', palette.blue], ['white', palette.white], ['ink', palette.ink]]) {
    await saveSVG(join(brand, 'logo', `local-minutes-symbol-${name}`), frame(640, 560, `<g transform="translate(-196 -232)">${mark(color)}</g>`, '', 'LocalMinutes audio-to-notes symbol'));
  }
  for (const dark of [false, true]) {
    const mode = dark ? 'dark' : 'light';
    const fg = dark ? '#F7F8FA' : palette.ink;
    const color = dark ? palette.darkBlue : palette.blue;
    const wordmark = frame(1100, 180,
      `<svg x="20" y="30" width="140" height="120" viewBox="244 278 544 468">${mark(color)}</svg>`
      + text(203, 126, 98, fg, 'LocalMinutes', 'font-weight="600" letter-spacing="-2.8"'), '', `LocalMinutes ${mode} wordmark`);
    await saveSVG(join(brand, 'logo', `local-minutes-wordmark-${mode}`), wordmark);
    await saveSVG(join(brand, 'splash', `local-minutes-splash-${mode}`), frame(393, 852, splashBody(dark), '', `LocalMinutes ${mode} splash screen`), 3);
  }
  const iconInner = iconsvg.replace(/^[\s\S]*?<svg\b[^>]*>/, '').replace(/<\/svg>\s*$/, '');
  const icon = (x, y, size, suffix) => `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 1024 1024">${iconInner.replaceAll('id="', `id="${suffix}-`).replaceAll('url(#', `url(#${suffix}-`)}</svg>`;
  const board = frame(1800, 1120,
    '<rect width="1800" height="1120" fill="#EAECF0"/>'
    + text(88, 88, 16, '#59616F', 'LOCALMINUTES', 'font-weight="600" letter-spacing="3"')
    + text(88, 153, 46, palette.ink, 'Every word. Yours.', 'font-weight="600" letter-spacing="-1.6"')
    + text(88, 192, 18, '#646A75', 'An identity for meetings that stay on your device.')
    + '<path d="M88 231H1712" stroke="#CFD3DB"/>'
    + icon(147, 298, 310, 'hero')
    + `<svg x="109" y="668" width="79" height="68" viewBox="244 278 544 468">${mark(palette.blue)}</svg>`
    + text(207, 718, 49, palette.ink, 'LocalMinutes', 'font-weight="600" letter-spacing="-1.5"')
    + text(109, 782, 17, '#646A75', 'Audio becomes notes. Everything stays local.')
    + '<path d="M109 837H590" stroke="#CFD3DB"/>'
    + icon(109, 870, 64, 'small64') + icon(200, 882, 40, 'small40') + icon(271, 890, 24, 'small24')
    + text(109, 971, 13, '#646A75', 'ONE MARK. CLEAR AT EVERY SIZE.', 'letter-spacing="1.5"')
    + phone(761, 281, false, 'light') + phone(1225, 281, true, 'dark')
    + text(936, 1090, 14, '#59616F', 'LIGHT', 'text-anchor="middle" letter-spacing="2"')
    + text(1400, 1090, 14, '#59616F', 'DARK', 'text-anchor="middle" letter-spacing="2"'), '', 'LocalMinutes logo and light and dark splash screen previews');
  await saveSVG(join(brand, 'local-minutes-preview'), board);
  const sizes = frame(900, 300,
    '<rect width="450" height="300" fill="#F5F5F7"/><rect x="450" width="450" height="300" fill="#09090B"/>'
    + icon(55, 80, 128, 'size128') + icon(217, 112, 64, 'size64') + icon(321, 128, 32, 'size32')
    + icon(505, 80, 128, 'dark128') + icon(667, 112, 64, 'dark64') + icon(771, 128, 32, 'dark32')
    + text(55, 250, 16, '#666B75', '128 px / 64 px / 32 px')
    + text(505, 250, 16, '#969BA5', '128 px / 64 px / 32 px'));
  await saveSVG(join(work, 'small-size-review'), sizes);
  console.log('Exported transparent logos, wordmarks, 1179 x 2556 splash PNGs, and the combined preview.');
}

if (process.argv[2] === 'prepare') await prepare();
else if (process.argv[2] === 'export') await exportArtwork();
else throw new Error('Usage: node build-brand-assets.mjs prepare|export');
