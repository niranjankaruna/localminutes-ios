import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const catalogue = JSON.parse(readFileSync('Models/Resources/SummaryCatalog.json', 'utf8'));
const parakeet = JSON.parse(readFileSync('Resources/ModelPacks/Parakeet-v3.json', 'utf8'));

for (const [platform, product] of [
  ['device', 'Release-iphoneos'], ['simulator', 'Debug-iphonesimulator'],
]) {
  test(`${platform} app bundles the complete pinned summary catalogue and Parakeet v3 descriptor`, () => {
    const app = resolve('build', platform, 'Build', 'Products', product, 'LocalMinutes.app');
    assert.deepEqual(JSON.parse(readFileSync(join(app, 'SummaryCatalog.json'), 'utf8')), catalogue);
    assert.deepEqual(JSON.parse(readFileSync(join(app, 'Parakeet-v3.json'), 'utf8')), parakeet);
    assert.equal(catalogue.families.flatMap(family => family.variants).length, 12);
    assert.equal(parakeet.parakeetConfiguration.decoderContract, 'parakeet-tdt-v3');
  });
}
