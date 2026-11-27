#!/usr/bin/env python3
"""生成 MacPulse 应用图标：深蓝渐变圆角方形 + 发光脉冲波形（无白色描边/同心圆网格）。

依赖 Pillow：python3 -m pip install pillow
产物写入仓库根目录下的 icons/，可再用 iconutil 生成 .icns。
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'icons')
SS = 4                      # 超采样倍数
BASE = 1024                 # 逻辑尺寸
S = BASE * SS               # 实际绘制尺寸


def sc(v):
    return int(round(v * SS))


def rounded_mask(size, radius, inset=0):
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset],
        radius=radius, fill=255
    )
    return m


def vgradient(size, top, bottom):
    w, h = size
    grad = Image.new('RGB', (1, h))
    px = grad.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        # 轻微 S 曲线让过渡更自然
        t = t * t * (3 - 2 * t)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return grad.resize((w, h), Image.BILINEAR)


def radial_glow(size, cx, cy, radius, color, max_alpha):
    """径向柔光层，用于顶部高光/脉冲发光。"""
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color + (max_alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius // 2))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # ---- 主体背景（深色渐变，呼应 app 深色仪表盘）----
    canvas = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    outer_mask = rounded_mask(S, radius=sc(232))
    bg = vgradient((S, S), top=(32, 48, 86), bottom=(12, 17, 30)).convert('RGBA')
    canvas.paste(bg, (0, 0), outer_mask)

    # 顶部冷色柔光，增加层次
    top_glow = radial_glow(S, sc(512), sc(180), sc(430), (90, 140, 235), 42)
    canvas = Image.alpha_composite(canvas, top_glow)
    # 重新用 mask 裁掉圆角外溢出的柔光
    canvas.putalpha(Image.composite(canvas.getchannel('A'), Image.new('L', (S, S), 0), outer_mask))

    # ---- 脉冲波形（ECG）----
    base_y = 556
    pts = [
        (150, base_y), (300, base_y), (330, 528), (360, base_y),
        (415, base_y), (448, 498), (476, 706), (505, 352),
        (534, 612), (562, base_y), (640, base_y), (672, 500),
        (704, base_y), (820, base_y), (874, base_y)
    ]
    pts_s = [(sc(x), sc(y)) for x, y in pts]

    # 发光层
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    glowd = ImageDraw.Draw(glow)
    glowd.line(pts_s, fill=(90, 165, 255, 210), width=sc(38), joint='curve')
    glow = glow.filter(ImageFilter.GaussianBlur(sc(26)))
    canvas = Image.alpha_composite(canvas, glow)
    glow2 = glow.filter(ImageFilter.GaussianBlur(sc(10)))
    canvas = Image.alpha_composite(canvas, glow2)

    # 清晰主线
    d = ImageDraw.Draw(canvas)
    d.line(pts_s, fill=(168, 214, 255, 255), width=sc(17), joint='curve')
    # 峰值点高亮
    peak = (505, 352)
    pr = sc(13)
    d.ellipse([sc(peak[0]) - pr, sc(peak[1]) - pr, sc(peak[0]) + pr, sc(peak[1]) + pr],
              fill=(235, 246, 255, 255))
    # 末端圆点
    end = pts_s[-1]
    er = sc(15)
    d.ellipse([end[0] - er, end[1] - er, end[0] + er, end[1] + er], fill=(168, 214, 255, 255))

    # 无描边：深蓝渐变直接延伸至圆角边缘，避免任何白色边框

    # 裁掉圆角外残余
    canvas.putalpha(Image.composite(canvas.getchannel('A'), Image.new('L', (S, S), 0), outer_mask))

    # 缩小到 1024 作为母图
    icon = canvas.resize((BASE, BASE), Image.LANCZOS)
    master = os.path.join(OUT_DIR, 'macpulse_1024.png')
    icon.save(master)
    print('saved master:', master)

    # ---- 生成 iconset 各尺寸 ----
    iconset = os.path.join(OUT_DIR, 'MacPulse.iconset')
    os.makedirs(iconset, exist_ok=True)
    for sz in [16, 32, 64, 128, 256, 512, 1024]:
        img = icon.resize((sz, sz), Image.LANCZOS)
        img.save(os.path.join(iconset, f'icon_{sz}x{sz}.png'))
        if sz <= 512:
            img2 = icon.resize((sz * 2, sz * 2), Image.LANCZOS)
            img2.save(os.path.join(iconset, f'icon_{sz}x{sz}@2x.png'))
    print('saved iconset:', iconset)


if __name__ == '__main__':
    main()
