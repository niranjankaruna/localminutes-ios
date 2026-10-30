import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const work = dirname(fileURLToPath(import.meta.url));
const delivery = resolve(work, '../..');
const repository = resolve(work, '../../../../..');
const catalog = join(repository, 'Resources', 'BrandAssets.xcassets');
const skillScripts = process.env.APP_ICON_SKILL_SCRIPTS || 'C:/Users/NiMo/.agents/skills/app-icon-gen/scripts';
const require = createRequire(join(skillScripts, 'package.json'));
const { Resvg } = require('@resvg/resvg-js');
const { PNG } = require('pngjs');
const info = { author: 'xcode', version: 1 };

async function writeCatalogJSON(folder, value) {
  const directory = join(catalog, folder);
  await mkdir(directory, { recursive: true });
  await writeFile(join(directory, 'Contents.json'), JSON.stringify(value, null, 2) + '\n');
}

await writeCatalogJSON('', { info });

// The App Store source must be square and opaque. Encode RGB, without even an
// unused alpha channel; keep the approved pixels and leave masking to iOS.
const icon = PNG.sync.read(await readFile(join(delivery, 'local-minutes.png')));
if (icon.width !== 1024 || icon.height !== 1024) throw new Error('The approved icon must be 1024 x 1024.');
for (let offset = 3; offset < icon.data.length; offset += 4) {
  if (icon.data[offset] !== 255) throw new Error('The approved icon must have an opaque square background.');
}
await writeCatalogJSON('AppIcon.appiconset', {
  images: [{ filename: 'LocalMinutes.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }], info,
});
await writeFile(join(catalog, 'AppIcon.appiconset', 'LocalMinutes.png'), PNG.sync.write(icon, { colorType: 2, inputColorType: 6, inputHasAlpha: true }));

const layers = await Promise.all(['02-audio-signal.svg', '03-written-minutes.svg'].map(async name => {
  const svg = await readFile(join(delivery, 'layers', name), 'utf8');
  return svg.replace(/^[\s\S]*?<svg\b[^>]*>/, '').replace(/<\/svg>\s*$/, '').replaceAll('#FFFFFF', '#000000');
}));
const mark = `<svg xmlns="http://www.w3.org/2000/svg" width="108" height="93" viewBox="244 278 544 468">${layers.join('')}</svg>`;
const images = [1, 2, 3].map(scale => ({
  filename: `LocalMinutesMark${scale === 1 ? '' : `@${scale}x`}.png`, idiom: 'universal', scale: `${scale}x`,
}));
await writeCatalogJSON('LocalMinutesMark.imageset', { images, info, properties: { 'template-rendering-intent': 'template' } });
for (let index = 0; index < images.length; index++) {
  const png = new Resvg(mark, { fitTo: { mode: 'zoom', value: index + 1 }, font: { loadSystemFonts: false } }).render().asPng();
  await writeFile(join(catalog, 'LocalMinutesMark.imageset', images[index].filename), png);
}

for (const [name, light, dark] of [
  ['LaunchBackground', '#F5F5F7', '#09090B'],
  ['LaunchAccent', '#0065D4', '#70ADFF'],
  ['LaunchText', '#17191F', '#F7F8FA'],
  ['LaunchSecondaryText', '#666B75', '#969BA5'],
]) {
  const color = hex => ({ 'color-space': 'srgb', components: {
    red: (parseInt(hex.slice(1, 3), 16) / 255).toFixed(10),
    green: (parseInt(hex.slice(3, 5), 16) / 255).toFixed(10),
    blue: (parseInt(hex.slice(5, 7), 16) / 255).toFixed(10), alpha: '1.000',
  } });
  await writeCatalogJSON(`${name}.colorset`, {
    colors: [
      { idiom: 'universal', color: color(light) },
      { idiom: 'universal', appearances: [{ appearance: 'luminosity', value: 'dark' }], color: color(dark) },
    ], info,
  });
}
console.log('Exported the approved RGB app icon, 1x/2x/3x template logo, and adaptive launch colors to Resources/BrandAssets.xcassets.');
