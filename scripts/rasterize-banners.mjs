#!/usr/bin/env node
/**
 * Regenerates the SDK's banner PNGs from apps/dashboard/public/support/banners.
 *
 *   node sdk/appwin-ios/scripts/rasterize-banners.mjs
 */
const { Resvg } = require('@resvg/resvg-js')
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '../../../..')
const src = path.join(root, 'apps/dashboard/public/support/banners')
const out = path.join(
  root,
  'sdk/appwin-ios/Sources/AppwinSupport/Resources/Banners',
)

fs.mkdirSync(out, { recursive: true })

const svgs = [
  'amicale.svg',
  'discret.svg',
  'serious.svg',
  'tile-a.svg',
  'tile-b.svg',
  'icon-ring-outer.svg',
  'icon-ring-mid.svg',
  'icon-ring-inner.svg',
  'icon-headset.svg',
  'icon-mic.svg',
]

for (const file of svgs) {
  const svg = fs.readFileSync(path.join(src, file))
  const resvg = new Resvg(svg, {
    fitTo: { mode: 'width', value: 900 },
    background: 'rgba(0,0,0,0)',
  })
  const png = resvg.render().asPng()
  const name = file.replace('.svg', '.png')
  fs.writeFileSync(path.join(out, name), png)
  console.log('wrote', name, png.length)
}

for (const file of [
  'emoji-wave.png',
  'emoji-laptop.png',
  'emoji-lifebuoy.png',
  'photo.png',
]) {
  fs.copyFileSync(path.join(src, file), path.join(out, file))
  console.log('copied', file)
}
