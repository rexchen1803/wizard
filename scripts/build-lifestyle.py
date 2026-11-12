#!/usr/bin/env python3
"""Create deterministic HTML photo compositions from reviewed native captures.

The browser projects the entire source PNG into the display quad. This script
does not generate or repaint App pixels, run the App, or install anything.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import html
import json
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]


def solve(matrix, values):
    rows = [list(map(float, row)) + [float(value)] for row, value in zip(matrix, values)]
    for column in range(8):
        pivot = max(range(column, 8), key=lambda index: abs(rows[index][column]))
        if abs(rows[pivot][column]) < 1e-12:
            raise ValueError("degenerate screen quad")
        rows[column], rows[pivot] = rows[pivot], rows[column]
        divisor = rows[column][column]
        rows[column] = [value / divisor for value in rows[column]]
        for index in range(8):
            if index != column:
                factor = rows[index][column]
                rows[index] = [a - factor * b for a, b in zip(rows[index], rows[column])]
    return [row[-1] for row in rows]


def projection(width, height, quad):
    source = [(0, 0), (width, 0), (width, height), (0, height)]
    matrix, values = [], []
    for (x, y), (u, v) in zip(source, quad):
        matrix.extend([[x, y, 1, 0, 0, 0, -u*x, -u*y],
                       [0, 0, 0, x, y, 1, -v*x, -v*y]])
        values.extend([u, v])
    a, b, c, d, e, f, g, h = solve(matrix, values)
    for (x, y), (u, v) in zip(source, quad):
        denominator = g*x + h*y + 1
        if abs((a*x+b*y+c)/denominator-u) > 1e-6 or abs((d*x+e*y+f)/denominator-v) > 1e-6:
            raise ValueError("screen projection does not preserve its corners")
    return [a, d, 0, g, b, e, 0, h, 0, 0, 1, 0, c, f, 0, 1]


def bound_input(base, record):
    original = base / record['file']
    path = original.resolve()
    if original.is_symlink() or not path.is_relative_to((ROOT/'assets/demo').resolve()):
        raise ValueError("composition input is outside the reviewed demo tree")
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != record['sha256']:
        raise ValueError(f"unbound composition input: {path.name}")
    return raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='new standalone HTML directory')
    args = parser.parse_args()
    if args.out.exists() or args.out.is_symlink():
        parser.error('output must not already exist')
    base = ROOT/'assets/demo/environments'
    scenes = json.loads((base/'SCENES.json').read_text())
    captures = json.loads((ROOT/'assets/demo/screens/CAPTURE-METADATA.json').read_text())
    if scenes['source_fingerprint'] != captures['source_fingerprint'] or scenes['build'] != captures['build']:
        parser.error('scene and native capture sources differ')
    native = {Path(item['file']).name: item for item in captures['captures']}
    documents, records = [], []
    for scene in scenes['scenes']:
        environment, screen = scene['environment'], scene['screen']
        capture = native[Path(screen['file']).name]
        if screen['sha256'] != capture['sha256'] or screen['pixels'] != capture['pixels']:
            parser.error('screen is not the recorded native capture')
        background, pixels = bound_input(base, environment), bound_input(base, screen)
        if pixels[:8] != b'\x89PNG\r\n\x1a\n' or list(struct.unpack('>II', pixels[16:24])) != screen['pixels']:
            parser.error('native screen dimensions differ')
        width, height = scene['canvas']
        if not all(0 <= x <= width and 0 <= y <= height for x, y in screen['canvas_quad']):
            parser.error('screen extends beyond the scene')
        transform = projection(*screen['pixels'], screen['canvas_quad'])
        matrix = ','.join(format(value, '.15g') for value in transform)
        dx, dy = environment['offset']
        ew, eh = environment['pixels']
        sw, sh = screen['pixels']
        title = html.escape(scene['id'])
        doc = f'''<!doctype html><html><head><meta charset="utf-8"><title>Wizard · {title}</title>
<style>html,body{{margin:0;width:{width}px;height:{height}px;overflow:hidden;background:#10101c}}
main{{position:relative;width:{width}px;height:{height}px;overflow:hidden}}
img{{position:absolute;left:0;top:0;display:block;max-width:none;transform-origin:0 0}}
#environment{{width:{ew}px;height:{eh}px;transform:translate({dx}px,{dy}px) scale({environment['scale']})}}
#native-screen{{width:{sw}px;height:{sh}px;transform:matrix3d({matrix});backface-visibility:hidden}}
</style></head><body><main data-scene="{title}">
<img id="environment" alt="Illustrative environment" src="data:image/jpeg;base64,{base64.b64encode(background).decode()}">
<img id="native-screen" alt="Unmodified native App Simulator capture" data-source-sha256="{screen['sha256']}" src="data:image/png;base64,{base64.b64encode(pixels).decode()}">
</main></body></html>'''
        documents.append((scene['id']+'.html', doc))
        records.append({'scene':scene['id'], 'screen_sha256':screen['sha256'],
                        'environment_sha256':environment['sha256'], 'matrix3d':transform,
                        'canvas':scene['canvas'], 'screen_repainted':False})
    args.out.mkdir(parents=True)
    for name, doc in documents:
        (args.out/name).write_text(doc)
    (args.out/'COMPOSITION-RECORD.json').write_text(json.dumps(records, indent=2)+'\n')
    print(json.dumps({'scenes':len(documents), 'native_screens_unchanged':True}))


if __name__ == '__main__':
    main()
