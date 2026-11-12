#!/usr/bin/env python3
"""Build the README campaign from licensed type and unmodified source images.

Requires fonttools 4.60.2. Run from the repository root; see assets/readme/SOURCES.md.
The optional design tool never builds, installs or changes the native App.
"""
from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
from pathlib import Path
from xml.sax.saxutils import escape

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont


CREAM, PINK, MUTED = '#FFF9CB', '#F7A6BE', '#DFB9D0'
GROUND, PLUM = '#10101C', '#21152D'
COPY = json.loads((Path(__file__).resolve().parents[1]/'assets/readme/COPY.json').read_text())
LANGUAGES = ('zh-CN', 'zh-TW', 'en', 'ja')


def translated(value, language):
    if language != 'zh-CN':
        table = COPY['translations'][language]
        if value in table:
            return table[value]
        if any('\u4e00' <= char <= '\u9fff' for char in value):
            raise ValueError(f'Missing {language} campaign copy: {value}')
    return value


class Face:
    def __init__(self, path: Path):
        f = TTFont(path)
        self.glyphs, self.cmap = f.getGlyphSet(), f.getBestCmap()
        self.metrics, self.upem = f['hmtx'].metrics, f['head'].unitsPerEm
        self.cache = {}

    def glyph(self, char):
        if char not in self.cache:
            name = self.cmap[ord(char)]
            glyph = self.glyphs[name]
            path, bounds = SVGPathPen(self.glyphs), BoundsPen(self.glyphs)
            glyph.draw(path)
            glyph.draw(bounds)
            self.cache[char] = (path.getCommands(), bounds.bounds, self.metrics[name][0])
        return self.cache[char]

    def layout(self, text):
        cursor, items, boxes = 0, [], []
        for char in text:
            path, box, advance = self.glyph(char)
            items.append((cursor, path))
            if box:
                boxes.append((cursor + box[0], box[1], cursor + box[2], box[3]))
            cursor += advance
        return items, (min(b[0] for b in boxes), min(b[1] for b in boxes),
                       max(b[2] for b in boxes), max(b[3] for b in boxes))


class Panel:
    def __init__(self, width, height, gutter, title, faces, mobile, ground=GROUND, language='zh-CN'):
        self.width, self.height, self.gutter = width, height, gutter
        self.title, self.faces, self.mobile = translated(title, language), faces, mobile
        self.language = language
        self.parts = [f'<rect width="{width}" height="{height}" fill="{ground}"/>']
        self.elements = []

    def text(self, value, baseline, size, face='bold', color=CREAM, x=None, limit=None, role='copy', localize=True):
        value = translated(value, self.language) if localize else value
        x = self.gutter if x is None else x
        limit = self.width - self.gutter - x if limit is None else limit
        font = self.faces[face]
        items, bounds = font.layout(value)
        scale = size / font.upem
        ink_width = (bounds[2] - bounds[0]) * scale
        if ink_width > limit + .01:
            raise ValueError(f'{self.title}: {value!r} exceeds {limit}: {ink_width}')
        paths = ''.join(f'<path d="{path}" transform="translate({cursor} 0)"/>'
                        for cursor, path in items if path)
        # Align the visible ink, rather than the font's unequal side bearings.
        origin = x - bounds[0] * scale
        self.parts.append(f'<g aria-label="{escape(value)}" fill="{color}" '
                          f'transform="translate({origin:.6f} {baseline}) scale({scale:.9f} {-scale:.9f})">{paths}</g>')
        self.elements.append({'role': role, 'text': value, 'left': x, 'right': x + ink_width,
                              'top': baseline - bounds[3] * scale, 'bottom': baseline - bounds[1] * scale})

    def wordmark(self, baseline):
        f = self.faces['display']
        _, box = f.layout('WIZARD')
        size = (self.width - 2 * self.gutter) * f.upem / (box[2] - box[0])
        self.text('WIZARD', baseline, size, 'display', role='wordmark')

    def image(self, path, x, y, w, h, role='image'):
        raw = path.read_bytes()
        encoded = base64.b64encode(raw).decode()
        mime = 'image/png' if path.suffix.lower() == '.png' else 'image/jpeg'
        self.parts.append(f'<image x="{x}" y="{y}" width="{w}" height="{h}" '
                          f'preserveAspectRatio="xMidYMid meet" href="data:{mime};base64,{encoded}"/>')
        self.elements.append({'role': role, 'source': path.name, 'sha256': hashlib.sha256(raw).hexdigest(),
                              'left': x, 'right': x + w, 'top': y, 'bottom': y + h})

    def arrow(self, y):
        end = self.width - self.gutter
        self.parts.append(f'<path d="M{end-68} {y}h64m-24-24 24 24-24 24" '
                          f'fill="none" stroke="{PINK}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>')

    def save(self, path):
        for item in self.elements:
            if not (0 <= item['left'] < item['right'] <= self.width + .01
                    and 0 <= item['top'] < item['bottom'] <= self.height + .01):
                raise ValueError(f'{self.title}: element falls outside the canvas: {item}')
        content = [e for e in self.elements if e['role'] != 'artwork']
        for index, first in enumerate(content):
            for second in content[index+1:]:
                if (min(first['right'], second['right']) > max(first['left'], second['left']) + .01
                        and min(first['bottom'], second['bottom']) > max(first['top'], second['top']) + .01):
                    raise ValueError(f'{self.title}: content overlaps: {first} / {second}')
        doc = f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
        doc += f'viewBox="0 0 {self.width} {self.height}" role="img"><title>{escape(self.title)}</title>'
        doc += ''.join(self.parts) + '</svg>\n'
        path.write_text(doc)
        return {'file': path.name, 'language': self.language, 'width': self.width, 'height': self.height,
                'gutter': self.gutter, 'elements': self.elements,
                'sha256': hashlib.sha256(doc.encode()).hexdigest()}


def hero(artwork, faces, mobile, language):
    w, g, hero_h = (760, 40, 840) if mobile else (1200, 64, 1120)
    p = Panel(w, hero_h, g, 'Wizard · 查看安装指南', faces, mobile, language=language)
    p.image(artwork, 0, 0, w, w * 9 / 16, 'artwork')
    fade_y = 320 if mobile else 510
    fade_h = 160 if mobile else 220
    p.parts.append(f'<defs><linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">'
                   f'<stop stop-color="{GROUND}" stop-opacity="0"/><stop offset="1" stop-color="{GROUND}"/></linearGradient></defs>'
                   f'<rect y="{fade_y}" width="{w}" height="{fade_h}" fill="url(#fade)"/>'
                   f'<rect y="{fade_y+fade_h}" width="{w}" height="{hero_h-fade_y-fade_h}" fill="{GROUND}"/>')
    p.wordmark(610 if mobile else 860)
    p.text('让闲置的 iPad，再次发光。', 700 if mobile else 950, 44, color=PINK)
    action_y = 780 if mobile else 1044
    p.text('安装指南', action_y, 40 if mobile else 38, color=PINK)
    end = p.elements[-1]['right']
    p.parts.append(f'<path d="M{g} {action_y+14}H{end} M{end+22} {action_y-15}h36m-13-13 13 13-13 13" '
                   f'fill="none" stroke="{PINK}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>')
    return p


def showcase(root, faces, mobile, capture, language):
    w, g, total = (760, 40, 1780) if mobile else (1200, 64, 1900)
    p = Panel(w, total, g, 'Wizard · 翻页时钟、壁纸图库与本地影像', faces, mobile, language=language)
    y = 0
    p.text('时钟与画面。', y + 120 if mobile else y + 140, 64)
    p.text('把喜欢的画面，留在屏幕上。', y + 188 if mobile else y + 210, 38 if mobile else 34, 'regular', MUTED)
    image_y = y + (245 if mobile else 270)
    image_w = w - 2 * g
    p.image(root/'assets/demo/home-miami.jpg', g, image_y, image_w, image_w * .75, 'native-capture')
    caption_y = image_y + image_w * .75 + (62 if mobile else 58)
    labels = {
        'zh-CN': ('iPad 实机截图', 'iPad 模拟器实截'),
        'zh-TW': ('iPad 實機截圖', 'iPad 模擬器截圖'),
        'en': ('Physical iPad', 'iPad Simulator'),
        'ja': ('iPad 実機キャプチャ', 'iPad シミュレータ')}
    label = labels[language][0 if capture['physical_device'] else 1]
    p.text(f"{label} · build {capture['build']}", caption_y, 34 if mobile else 26,
           'regular', MUTED, role='provenance', localize=False)
    notes = {'en':'Chinese menus · original App capture',
             'ja':'中国語メニュー · アプリの実キャプチャ'}
    if language in notes:
        p.text(notes[language], caption_y + (50 if mobile else 42),
               32 if mobile else 26, 'regular', MUTED, role='provenance', localize=False)
    if mobile:
        p.text('壁纸图库', y + 995, 60)
        p.image(root/'assets/demo/gallery-miami.jpg', g, y + 1060, image_w, image_w * .75, 'native-capture')
        p.text('分类、收藏与照片导入。', y + 1640, 38, 'regular', MUTED)
        p.text('也能调整时钟布局与字体。', y + 1710, 38, 'regular', MUTED)
    else:
        cw, gap = (w - 2 * g - 32) / 2, 32
        row_y = y + 1240
        p.image(root/'assets/demo/gallery-miami.jpg', g, row_y, cw, cw*.75, 'native-capture')
        right = g + cw + gap
        title_top = faces['bold'].layout(translated('布局，', language))[1][3] * 64 / faces['bold'].upem
        p.text('布局，', row_y + title_top, 64, x=right, limit=cw)
        p.text('随你心意。', row_y + title_top + 92, 64, x=right, limit=cw)
        p.text('移动时钟与日历，', row_y + 250, 32, 'regular', MUTED, x=right, limit=cw)
        p.text('字体与壁纸裁切，都能调整。', row_y + 305, 32, 'regular', MUTED, x=right, limit=cw)
        p.text('壁纸图库', y + 1720, 52, limit=cw)
        p.text('分类、收藏与照片导入。', y + 1790, 30, 'regular', MUTED, limit=cw)
    return p


def lifestyle(root, faces, mobile, language):
    w, g, h = (760, 40, 2780) if mobile else (1200, 64, 1510)
    p = Panel(w, h, g, '生活里的 Wizard。', faces, mobile, language=language)
    p.text('生活里的 Wizard。', 120 if mobile else 140, 56 if mobile else 64)
    p.text('书桌、床头与客厅。', 188 if mobile else 210, 34, 'regular', MUTED)
    photos = [('website-study', '暖光书房 · 网站场景'), ('daylight-desk', '日光书桌 · iPad 2'),
              ('linen-bedside', '床头一角 · iPad 4'), ('dusk-console', '暮色客厅 · iPad Air')]
    cw = w-2*g if mobile else (w-2*g-32)/2
    for index, (name, label) in enumerate(photos):
        x = g if mobile else g+(index % 2)*(cw+32)
        y = 245+index*(cw*2/3+120) if mobile else 270+(index//2)*490
        p.image(root/f'assets/demo/environments/{name}.jpg', x, y, cw, cw*2/3, 'lifestyle-composite')
        p.text(label, y+cw*2/3+(50 if mobile else 58), 32 if mobile else 30,
               'regular', MUTED, x=x, limit=cw)
    p.text('场景合成 · 屏幕为原生截图', 2550 if mobile else 1260,
           28 if mobile else 28, 'regular', MUTED, role='provenance')
    p.text('iPad Simulator · build 20261112.41', 2604 if mobile else 1316,
           28 if mobile else 26, 'regular', MUTED, role='provenance', localize=False)
    p.text('查看场景与截图', h-70, 36)
    p.arrow(h-92)
    return p


def variations(root, faces, mobile, language):
    w, g, h = (760, 40, 1420) if mobile else (1200, 64, 1940)
    p = Panel(w, h, g, '每一种心情，都有画面。', faces, mobile, language=language)
    p.text('每一种心情，都有画面。', 120 if mobile else 140, 52 if mobile else 64)
    p.text('六种壁纸与时间布局。', 188 if mobile else 210, 34, 'regular', MUTED)
    shots = [('sunset-poster','落日插画'), ('island-minimal','海岛留白'),
             ('night-city','夜景与秒钟'), ('city-calendar','城市与日历'),
             ('green-retreat','绿意角落'), ('palm-drive','棕榈日光')]
    gap = 24 if mobile else 32
    cw = (w-2*g-gap)/2
    for index, (name, label) in enumerate(shots):
        x = g+(index % 2)*(cw+gap)
        y = (245 if mobile else 270)+(index//2)*(310 if mobile else 480)
        p.image(root/f'assets/demo/screens/{name}.jpg', x, y, cw, cw*.75, 'native-capture')
        p.text(label, y+cw*.75+(44 if mobile else 54), 26 if mobile else 30,
               'regular', MUTED, x=x, limit=cw)
    p.text('iPad Simulator · build 20261112.41', 1234 if mobile else 1760,
           28 if mobile else 26, 'regular', MUTED, role='provenance', localize=False)
    p.text('查看原始截图', h-70, 36)
    p.arrow(h-92)
    return p


def collection(city, faces, mobile, language):
    w, g, h = (760, 40, 1110) if mobile else (1200, 64, 1320)
    p = Panel(w, h, g, 'Vice City 素材合集 · 图片、视频与原始素材', faces, mobile, PLUM, language)
    p.text('VICE CITY.', 150 if mobile else 180, 126 if mobile else 166, 'display')
    p.text('把喜欢的画面，留在图库。', 246 if mobile else 278, 48 if mobile else 56)
    iw, iy = w-2*g, 314 if mobile else 350
    p.image(city, g, iy, iw, iw*9/16, 'artwork')
    bottom = iy + iw*9/16
    p.text('228 张图片 · 2 段视频', bottom+83, 38 if mobile else 34, 'regular', MUTED)
    p.text('另含原始素材包', bottom+147, 38 if mobile else 34, 'regular', MUTED)
    p.text('查看素材与说明', h-86, 48)
    p.arrow(h-107)
    return p


def action(faces, mobile, kind, language):
    w, g, h = (760, 40, 276) if mobile else (1200, 64, 246)
    titles = {'install':'安装 Wizard', 'agent':'交给 Agent', 'source':'从源码构建'}
    details = {'install':'预览安装包与设备指南', 'agent':'一次性安装提示词', 'source':'构建说明、源码与贡献方式'}
    p = Panel(w, h, g, titles[kind], faces, mobile, PLUM if kind!='source' else GROUND, language)
    p.text(titles[kind], 116, 58 if mobile else 60, limit=w-2*g-100)
    p.text(details[kind], 202 if mobile else 188, 36 if mobile else 32, 'regular', MUTED)
    p.arrow(106)
    return p


def footer(faces, mobile, language):
    w, g, h = (760, 40, 400) if mobile else (1200, 64, 400)
    p = Panel(w, h, g, 'Wizard · 项目与第三方素材许可', faces, mobile, language=language)
    p.text('WIZARD', 114, 76, 'display')
    p.text('原生 iPad 应用 · 非官方开源项目', 190, 34 if mobile else 32, 'regular', MUTED)
    p.text('代码 MIT · 字体 OFL 1.1', 256, 32 if mobile else 28, 'regular', MUTED)
    p.text('GTA VI 素材 © Rockstar Games 及相关权利人', 314, 28, 'regular', MUTED)
    p.text('Made by Rex Chen', h-28, 20, 'display', MUTED)
    return p


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--cjk-regular', type=Path, required=True)
    parser.add_argument('--cjk-bold', type=Path, required=True)
    parser.add_argument('--traditional-regular', type=Path, required=True)
    parser.add_argument('--traditional-bold', type=Path, required=True)
    parser.add_argument('--japanese-regular', type=Path, required=True)
    parser.add_argument('--japanese-bold', type=Path, required=True)
    parser.add_argument('--hero-art', type=Path, required=True)
    parser.add_argument('--city-art', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    a = parser.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    capture = json.loads((a.root/'assets/demo/CAPTURE-METADATA.json').read_text())
    build_tree = ast.parse((a.root/'scripts/build-preview.py').read_text())
    inputs = next(ast.literal_eval(n.value) for n in build_tree.body if isinstance(n, ast.Assign)
                  and any(isinstance(t, ast.Name) and t.id == 'INPUTS' for t in n.targets))
    snapshot = ''.join(f"{n} {hashlib.sha256((a.root/'App'/n).read_bytes()).hexdigest()}\n" for n in inputs)
    if hashlib.sha256(snapshot.encode()).hexdigest() != capture['source_fingerprint']:
        parser.error('Native capture source is stale; recapture before rebuilding the showcase')
    app_font = a.root/'App/Resources/Anton-Regular.ttf'
    if hashlib.sha256(app_font.read_bytes()).hexdigest() != capture['font']['sha256']:
        parser.error('Capture display font differs from the actual App font')
    for name in ('home-miami.jpg', 'gallery-miami.jpg'):
        item = next(c for c in capture['captures'] if c['file'] == name)
        if hashlib.sha256((a.root/'assets/demo'/name).read_bytes()).hexdigest() != item['sha256']:
            parser.error(f'Unbound native image: {name}')
    native_scenes = json.loads((a.root/'assets/demo/screens/CAPTURE-METADATA.json').read_text())
    photo_scenes = json.loads((a.root/'assets/demo/environments/SCENES.json').read_text())
    for manifest in (native_scenes, photo_scenes):
        if manifest['source_fingerprint'] != capture['source_fingerprint'] or manifest['build'] != capture['build']:
            parser.error('Lifestyle capture source is stale')
    for shot in native_scenes['captures']:
        for path_key, hash_key in (('file','sha256'), ('web_file','web_sha256')):
            if hashlib.sha256((a.root/shot[path_key]).read_bytes()).hexdigest() != shot[hash_key]:
                parser.error('Unbound native scene image')
    for scene in photo_scenes['scenes']:
        if hashlib.sha256((a.root/'assets/demo/environments'/scene['file']).read_bytes()).hexdigest() != scene['sha256']:
            parser.error('Unbound lifestyle composite')
    display = Face(app_font)
    font_paths = {'zh-CN':(a.cjk_regular,a.cjk_bold), 'zh-TW':(a.traditional_regular,a.traditional_bold),
                  'en':(a.cjk_regular,a.cjk_bold), 'ja':(a.japanese_regular,a.japanese_bold)}
    records = []
    for language in LANGUAGES:
        regular, bold = font_paths[language]
        faces = {'display':display,'regular':Face(regular),'bold':Face(bold)}
        for mobile in (False, True):
            suffix = {'zh-CN':'','zh-TW':'-zh-tw','en':'-en','ja':'-ja'}[language] + ('-mobile' if mobile else '')
            panels = {'hero':hero(a.hero_art,faces,mobile,language),
                      'showcase':showcase(a.root,faces,mobile,capture,language),
                      'lifestyle':lifestyle(a.root,faces,mobile,language),
                      'variations':variations(a.root,faces,mobile,language),
                      'collection':collection(a.city_art,faces,mobile,language),
                      **{n:action(faces,mobile,n,language) for n in ('install','agent','source')},
                      'footer':footer(faces,mobile,language)}
            for name, panel in panels.items():
                records.append(panel.save(a.out/f'{name}{suffix}.svg'))
    manifest = {'schema':'wizard.campaign-layout.v3', 'languages':list(LANGUAGES),
                'native_capture_build':capture['build'],
                'native_source_fingerprint':capture['source_fingerprint'],
                'font_sha256':{label:hashlib.sha256(path.read_bytes()).hexdigest()
                               for label,path in [('Anton-Regular.ttf',app_font),
                                                  ('NotoSansCJKsc-Regular.otf',a.cjk_regular),
                                                  ('NotoSansCJKsc-Bold.otf',a.cjk_bold),
                                                  ('NotoSansCJKtc-Regular.otf',a.traditional_regular),
                                                  ('NotoSansCJKtc-Bold.otf',a.traditional_bold),
                                                  ('NotoSansCJKjp-Regular.otf',a.japanese_regular),
                                                  ('NotoSansCJKjp-Bold.otf',a.japanese_bold)]},
                'panels':records}
    (a.out/'LAYOUT.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'panels':len(records),'all_text_outlined':True}))


if __name__ == '__main__':
    main()
