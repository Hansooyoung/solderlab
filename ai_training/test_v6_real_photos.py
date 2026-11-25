"""
Test & visualize upgraded Hue-Clustered PCB Segmentation + WhiteFloor Metallic Cone Detector
+ 16-Ray Uncut Wire Lead Rejection + Soldy-Net-V6 inference across 14 real 12MP photos.
"""

import os
import glob
import json
import math
import time
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_fill_holes, binary_dilation, label, maximum_filter
from soldy_features import extract_features_from_pil

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
MODEL_JSON = os.path.join(REPO_ROOT, 'assets', 'models', 'soldy_v6_model.json')
SCRATCH_OUT = os.path.join(os.path.dirname(__file__), 'scratch', 'cv_v6_real_test')
os.makedirs(SCRATCH_OUT, exist_ok=True)


def load_v6():
    with open(MODEL_JSON, 'r', encoding='utf-8') as f:
        return json.load(f)


def eval_tree(nodes, x):
    idx = 0
    while True:
        nd = nodes[idx]
        if nd[0] == 1:
            return nd[1:]
        idx = nd[3] if x[nd[1]] <= nd[2] else nd[4]


def predict_v6(model, im: Image.Image):
    x = extract_features_from_pil(im)
    mean = np.array(model['scaler_mean'], dtype=np.float32)
    std = np.array(model['scaler_std'], dtype=np.float32)
    xz = (x - mean) / std

    p_mlp = np.zeros(7, dtype=np.float32)
    for m in model['mlps']:
        z1 = np.maximum(0.0, xz @ np.array(m['W1'], dtype=np.float32) + np.array(m['b1'], dtype=np.float32))
        z2 = np.maximum(0.0, z1 @ np.array(m['W2'], dtype=np.float32) + np.array(m['b2'], dtype=np.float32))
        logits = z2 @ np.array(m['W3'], dtype=np.float32) + np.array(m['b3'], dtype=np.float32)
        logits -= logits.max()
        ex = np.exp(np.clip(logits, -30.0, 30.0))
        p_mlp += ex / ex.sum()
    p_mlp /= len(model['mlps'])

    p_rf = np.mean([eval_tree(t, x) for t in model['trees']], axis=0)
    w_mlp = model['mlp_weight']
    probs = w_mlp * p_mlp + (1.0 - w_mlp) * p_rf
    cls_idx = int(probs.argmax())
    return model['classes'][cls_idx], float(probs[cls_idx]), probs


def hue_sector(r, g, b, sat, luma):
    chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    dom_red = (chroma >= 35.0) & (sat >= 0.36) & (r > g + 35.0) & (r > b + 20.0) & (luma >= 22.0) & (luma <= 185.0)
    dom_green = (chroma >= 20.0) & (sat >= 0.24) & (g > r + 14.0) & (g > b + 12.0) & (luma >= 22.0) & (luma <= 185.0)
    dom_blue = (chroma >= 24.0) & (sat >= 0.26) & (b > r + 20.0) & (b > g + 12.0) & (luma >= 20.0) & (luma <= 185.0)
    dom_yellow = (chroma >= 40.0) & (sat >= 0.38) & (r > b + 40.0) & (g > b + 30.0) & (np.abs(r - g) < 55.0) & (luma >= 55.0) & (luma <= 205.0)
    return dom_red, dom_green, dom_blue, dom_yellow


def segment_pcb_and_detect(im_rgb: Image.Image, max_joints: int = 200):
    orig_w, orig_h = im_rgb.size
    long_side = max(orig_w, orig_h)
    sc = min(1.0, 1200.0 / long_side)
    nw = max(48, int(round(orig_w * sc)))
    nh = max(48, int(round(orig_h * sc)))
    sm = im_rgb.resize((nw, nh), Image.Resampling.BILINEAR)
    arr = np.asarray(sm, dtype=np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    sat = chroma / (mx + 1.0)
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    white_floor = mn

    mean_sat = float(sat.mean())
    if float((luma > 210).mean()) > 0.45 and mean_sat < 0.14:
        return [], (nw, nh)

    d_red, d_green, d_blue, d_yellow = hue_sector(r, g, b, sat, luma)
    families = [
        ('RED', d_red),
        ('GREEN', d_green),
        ('BLUE', d_blue),
        ('YELLOW', d_yellow),
    ]

    best_mask = None
    best_family_name = 'DARK'
    best_family_score = 0.0
    total_px = float(nw * nh)
    for fname, fmask in families:
        cnt = int(fmask.sum())
        if cnt < total_px * 0.022:
            continue
        mean_f_sat = float(sat[fmask].mean())
        gsum = np.add.reduceat(
            np.add.reduceat(fmask.astype(np.int32), np.arange(0, nh, 12), axis=0),
            np.arange(0, nw, 12),
            axis=1,
        )
        dense_blocks = int((gsum >= 55).sum())
        if dense_blocks < 10:
            continue
        score = dense_blocks * (mean_f_sat ** 1.5) * 100.0
        if score > best_family_score:
            best_family_score = score
            best_mask = fmask
            best_family_name = fname

    if best_mask is None:
        smooth = np.zeros_like(luma, dtype=bool)
        smooth[:, 1:-1] = np.abs(luma[:, 2:] - luma[:, :-2]) < 14.0
        dark_pcb = (luma < 52.0) & (sat < 0.25) & smooth
        if int(dark_pcb.sum()) >= total_px * 0.08:
            if int(((luma > 165.0) & (sat < 0.25)).sum()) > 30:
                best_mask = dark_pcb
        if best_mask is None:
            return [], (nw, nh)

    blk = 8
    gh, gw = (nh + blk - 1) // blk, (nw + blk - 1) // blk
    padded = np.zeros((gh * blk, gw * blk), dtype=np.uint8)
    padded[:nh, :nw] = best_mask.astype(np.uint8)
    grid_frac = padded.reshape(gh, blk, gw, blk).mean(axis=(1, 3))
    gmask = grid_frac >= 0.22
    closed = binary_fill_holes(binary_dilation(gmask, iterations=1))
    lbl, nlbl = label(closed)
    if nlbl == 0:
        return [], (nw, nh)
    areas = np.bincount(lbl.ravel())
    areas[0] = 0
    max_area = int(areas.max())
    if max_area < 6:
        return [], (nw, nh)
    keep_lbls = [k for k in range(1, len(areas)) if areas[k] >= max(6, max_area * 0.25)]
    keep_grid = np.isin(lbl, keep_lbls)
    core_grid = binary_fill_holes(gmask)
    px_board_region = np.repeat(
        np.repeat(keep_grid & binary_dilation(core_grid, iterations=1), blk, axis=0),
        blk,
        axis=1,
    )[:nh, :nw]

    board_color_px = px_board_region & best_mask
    bg_lumas = luma[board_color_px]
    bg_wf = white_floor[board_color_px]
    if len(bg_lumas) < 40:
        return [], (nw, nh)
    board_mean = float(bg_lumas.mean())
    board_std = float(bg_lumas.std())
    wf_mean = float(bg_wf.mean())
    wf_std = float(bg_wf.std())

    solder_luma_thr = min(195.0, max(92.0, board_mean + max(26.0, board_std * 1.05)))
    solder_wf_thr = min(160.0, max(54.0, wf_mean + max(28.0, wf_std * 1.5)))
    halo_wf_thr = min(140.0, max(40.0, wf_mean + max(17.0, wf_std * 0.95)))
    halo_luma_thr = min(175.0, max(78.0, board_mean + max(16.0, board_std * 0.65)))
    max_joint_sat = 0.44 if best_family_name == 'RED' else 0.34

    peaks = []
    min_r = max(3, int(round(min(nw, nh) * 0.004)))
    max_trace = int(min(48, max(24, min(nw, nh) * 0.055)))
    angles = [i * math.pi / 8.0 for i in range(16)]
    cos_a = [math.cos(a) for a in angles]
    sin_a = [math.sin(a) for a in angles]

    metal_score = np.minimum(luma, white_floor * 1.35 + 15.0)
    win_max = maximum_filter(metal_score, size=9)
    cand_ys, cand_xs = np.where(
        px_board_region
        & (luma >= solder_luma_thr)
        & (white_floor >= solder_wf_thr)
        & (sat <= max_joint_sat)
        & (metal_score >= win_max - 0.1)
    )

    for y, x in zip(cand_ys.tolist(), cand_xs.tolist()):
        if y < 6 or y >= nh - 6 or x < 6 or x >= nw - 6:
            continue
        v = float(luma[y, x])

        yA, yB = max(0, y - 22), min(nh, y + 23)
        xA, xB = max(0, x - 22), min(nw, x + 23)
        if float(best_mask[yA:yB, xA:xB].mean()) < 0.14:
            continue

        # 16 radial metallic extent trace with 2px specular-ripple gap bridge along long thin wires
        radii = []
        wire_radii = []
        soft_halo_luma = halo_luma_thr * 0.85
        soft_halo_wf = halo_wf_thr * 0.82
        for ai in range(16):
            ca, sa = cos_a[ai], sin_a[ai]
            dist = 0
            wdist = 0
            gap = 0
            solid_broken = False
            for step in range(1, max_trace + 1):
                rx = int(round(x + ca * step))
                ry = int(round(y + sa * step))
                if rx < 1 or rx >= nw - 1 or ry < 1 or ry >= nh - 1:
                    break
                is_strict = (
                    luma[ry, rx] >= halo_luma_thr
                    and white_floor[ry, rx] >= halo_wf_thr
                    and sat[ry, rx] <= (max_joint_sat + 0.06)
                    and px_board_region[ry, rx]
                )
                is_wire = (
                    luma[ry, rx] >= soft_halo_luma
                    and white_floor[ry, rx] >= soft_halo_wf
                    and sat[ry, rx] <= (max_joint_sat + 0.08)
                )
                if is_strict and not solid_broken:
                    dist = step
                else:
                    solid_broken = True
                if is_wire:
                    wdist = step
                    gap = 0
                else:
                    gap += 1
                    if gap > 2:
                        break
            radii.append(dist)
            wire_radii.append(wdist)

        diams = [radii[k] + radii[k + 8] for k in range(8)]
        w_diams = [wire_radii[k] + wire_radii[k + 8] for k in range(8)]
        sorted_d = sorted(diams)
        sorted_wd = sorted(w_diams)
        min_diam = sorted_d[0]
        p25_diam = sorted_d[2]
        med_diam = sorted_d[4]
        max_wdiam = sorted_wd[-1]
        max_wk = w_diams.index(max_wdiam)
        opp_wmin = min(wire_radii[max_wk], wire_radii[max_wk + 8])
        perp_wdiam = w_diams[(max_wk + 4) % 8]

        if med_diam < max(5, min_r * 1.4):
            continue

        # REJECT 1D UNCUT COMPONENT WIRE LEADS:
        # 1) Long metallic axis (with 2px glare gap bridging) extending on BOTH sides of peak (opp_wmin >= 5)
        #    while perpendicular wire cross-section (perp_wdiam / p25_diam) is narrow (<= 7px)!
        w_aspect = max_wdiam / max(1.0, float(perp_wdiam))
        if perp_wdiam <= 7 and max_wdiam >= 16 and opp_wmin >= 5 and w_aspect >= 2.3:
            continue
        if p25_diam <= 6 and max_wdiam >= 14 and opp_wmin >= 4 and (max_wdiam / max(1.0, float(p25_diam))) >= 2.3:
            continue
        if min_diam <= 3 and max_wdiam >= 13:
            continue

        # Reject huge white background holes/paper sheets & bloat
        if med_diam > min(nw, nh) * 0.058:
            continue

        aspect = sorted_d[-1] / max(1.0, float(p25_diam))
        box_d = min(56.0, max(22.0, min(med_diam * 2.0, p25_diam * 2.5)))
        score = float(white_floor[y, x]) + v * 0.4 + p25_diam * 8.0 - max(0.0, aspect - 2.0) * 14.0
        peaks.append((score, x, y, box_d))

    peaks.sort(reverse=True, key=lambda t: t[0])
    selected = []
    for _, x, y, box_d in peaks:
        if len(selected) >= max_joints:
            break
        half = box_d * 0.5
        if any(abs(x - sx) < (half + sh) * 0.54 and abs(y - sy) < (half + sh) * 0.54 for sx, sy, sh in selected):
            continue
        selected.append((x, y, half))

    return [
        (
            max(0.0, min(1.0, x / nw)),
            max(0.0, min(1.0, y / nh)),
            min(0.32, (half * 2.0) / nw),
            min(0.32, (half * 2.0) / nh),
        )
        for x, y, half in selected
    ], (nw, nh)


def main():
    import sys
    model = load_v6()
    target_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO_ROOT, 'test', 'fixtures')
    photos = sorted(set(glob.glob(os.path.join(target_dir, '*.jpg'))))
    COLORS = {
        'PASS_NORMAL': (34, 197, 94),
        'D1_BRIDGE': (239, 68, 68),
        'D2_COLD': (245, 158, 11),
        'D3_INSUFFICIENT': (234, 179, 8),
        'D4_EXCESS': (249, 115, 22),
        'D5_PINHOLE': (168, 85, 247),
    }

    for ip in photos:
        t0 = time.time()
        im = Image.open(ip).convert('RGB')
        iw, ih = im.size
        boxes, _ = segment_pcb_and_detect(im)
        kept = 0
        rejected_ns = 0
        cls_counts = {}
        vis = im.resize((1200, int(1200 * ih / iw)), Image.Resampling.BILINEAR)
        vw, vh = vis.size
        draw = ImageDraw.Draw(vis)

        for cx, cy, bw, bh in boxes:
            pad = 1.0
            px1 = max(0, int((cx - bw * pad / 2) * iw))
            py1 = max(0, int((cy - bh * pad / 2) * ih))
            px2 = min(iw, int((cx + bw * pad / 2) * iw))
            py2 = min(ih, int((cy + bh * pad / 2) * ih))
            if px2 - px1 < 12 or py2 - py1 < 12:
                continue
            crop = im.crop((px1, py1, px2, py2))
            cname, conf, probs = predict_v6(model, crop)
            p_ns = float(probs[6])
            vx1, vy1 = int((cx - bw / 2) * vw), int((cy - bh / 2) * vh)
            vx2, vy2 = int((cx + bw / 2) * vw), int((cy + bh / 2) * vh)
            if p_ns >= 0.52:
                rejected_ns += 1
                draw.rectangle([vx1, vy1, vx2, vy2], outline=(100, 116, 139), width=1)
                continue
            kept += 1
            cls_counts[cname] = cls_counts.get(cname, 0) + 1
            col = COLORS.get(cname, (255, 255, 255))
            draw.rectangle([vx1, vy1, vx2, vy2], outline=col, width=3)
            draw.text((vx1, max(0, vy1 - 12)), f'{cname[:6]} {int(conf*100)}%', fill=col)

        dt = (time.time() - t0) * 1000.0
        tag = os.path.basename(ip)
        vis.save(os.path.join(SCRATCH_OUT, tag))
        print(f'{tag:36s} | raw={len(boxes):2d} kept={kept:2d} ns={rejected_ns:2d} ({dt:4.0f}ms) | {cls_counts}')


if __name__ == '__main__':
    main()
