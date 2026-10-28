#!/usr/bin/env python3
"""Render the original Saptak vector identity into Apple asset-catalog sizes."""
from pathlib import Path
from copy import deepcopy
import json
import shutil
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
renderer = shutil.which('rsvg-convert')
if not renderer:
    raise SystemExit('Install librsvg for the development-only rsvg-convert tool.')
source = root / 'Design/AppIcon.svg'
namespace = 'http://www.w3.org/2000/svg'
ET.register_namespace('', namespace)
svg = ET.parse(source).getroot()
svg.set('width', '1024')
svg.set('height', '1024')
svg.find(f'{{{namespace}}}title').text = 'Saptak app icon: plum sound marks on rose'
svg.find(f'{{{namespace}}}desc').text = 'Seven plum musical stems and an octave dot on a rose background.'
for node in list(svg):
    if node.get('fill') == 'none' and node.get('stroke') == '#54244F':
        svg.remove(node)
for node in svg.iter():
    if node.tag in (f'{{{namespace}}}rect', f'{{{namespace}}}circle'):
        if node.get('width') == '256':
            node.set('fill', '#E8A6BC')
        else:
            node.set('fill', '#54244F')
# Center visible marks (bounds 32...230, 38...224) on the 256-point canvas.
marks = svg.find(f'{{{namespace}}}g[@id="sound-mark"]')
if marks is None:
    marks = ET.SubElement(svg, f'{{{namespace}}}g', {'id': 'sound-mark'})
    for node in list(svg):
        if node.tag in (f'{{{namespace}}}rect', f'{{{namespace}}}circle') and node.get('width') != '256':
            svg.remove(node)
            marks.append(node)
marks.set('transform', 'translate(-3 -3)')
ET.ElementTree(svg).write(source, encoding='unicode', xml_declaration=True)
subprocess.run([renderer, '-o', str(source.with_suffix('.png')), str(source)], check=True)
# macOS does not apply the iOS Home Screen mask. Give its image transparent
# margins and a rounded body within the full canvas, including runtime Dock use.
mac = deepcopy(svg)
mac.find(f'{{{namespace}}}title').text = 'Saptak macOS icon: inset rounded rose body with plum marks'
mac.find(f'{{{namespace}}}desc').text = 'Transparent outer padding keeps the rose icon visually aligned with other Mac apps.'
artwork = ET.Element(f'{{{namespace}}}g', dict(transform='translate(25 25) scale(0.8046875)'))
for child in list(mac):
    if child.tag not in (f'{{{namespace}}}title', f'{{{namespace}}}desc'):
        mac.remove(child)
        if child.tag == f'{{{namespace}}}rect' and child.get('width') == '256':
            child.set('rx', '56')
        artwork.append(child)
mac.append(artwork)
mac_source = source.with_name('AppIcon-macOS.svg')
ET.ElementTree(mac).write(mac_source, encoding='unicode', xml_declaration=True)
subprocess.run([renderer, '-o', str(mac_source.with_suffix('.png')), str(mac_source)], check=True)

assets = root / 'App/Assets.xcassets'
icons = assets / 'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
info = dict(version=1, author='xcode')
(assets / 'Contents.json').write_text(json.dumps(dict(info=info), indent=2) + '\n')
entries = []
rendered = set()
# Explicit entries support iOS 16 and macOS 13 without requiring a newer icon format.
for idiom, points, scales in [
    ('iphone', [20, 29, 40, 60], [2, 3]),
    ('ipad', [20, 29, 40, 76], [1, 2]),
    ('ipad', [83.5], [2]),
    ('ios-marketing', [1024], [1]),
    ('mac', [16, 32, 128, 256, 512], [1, 2]),
]:
    for size in points:
        for scale in scales:
            pixels = int(size * scale)
            is_mac = idiom == 'mac'
            filename = f'icon-mac-{pixels}.png' if is_mac else f'icon-{pixels}.png'
            render_key = (is_mac, pixels)
            if render_key not in rendered:
                subprocess.run([renderer, '-w', str(pixels), '-h', str(pixels), '-o', str(icons / filename), str(mac_source if is_mac else source)], check=True)
                rendered.add(render_key)
            entries.append(dict(idiom=idiom, size=f'{size}x{size}', scale=f'{scale}x', filename=filename))
referenced = {entry['filename'] for entry in entries}
for old in icons.glob('icon-*.png'):
    if old.name not in referenced:
        old.unlink()
(icons / 'Contents.json').write_text(json.dumps(dict(images=entries, info=info), indent=2) + '\n')
print(f'Rendered {len(entries)} icon slots from the vector identity.')
