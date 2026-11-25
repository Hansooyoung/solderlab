"""
Exact 48-dimensional domain-invariant feature extractor for Soldy-Net-V6.
Must stay 100% mathematically aligned with lib/services/ai/solder_model_engine.dart!
"""

import math
import numpy as np
from PIL import Image

FEATURE_COUNT = 48

# Precompute 32x32 normalized geometry grid
GRID_N = 32
_ys, _xs = np.mgrid[0:GRID_N, 0:GRID_N].astype(np.float32)
_dx = (_xs - 15.5) / 15.5
_dy = (_ys - 15.5) / 15.5
_rad = np.sqrt(_dx * _dx + _dy * _dy)

MASK_CORE = _rad <= 0.30
MASK_MID = (_rad > 0.30) & (_rad <= 0.62)
MASK_OUTER = _rad > 0.62
MASK_IN60 = _rad <= 0.60
MASK_IN65 = _rad <= 0.65
MASK_IN75 = _rad <= 0.75
MASK_CORE45 = _rad <= 0.45
MASK_CORE28 = _rad <= 0.28
MASK_RING_DONUT = (_rad >= 0.25) & (_rad <= 0.50)
MASK_CENTER18 = _rad <= 0.18
MASK_CORNERS = (_rad > 0.88)

_RAYS = [
    (1.0, 0.0), (0.70710678, 0.70710678), (0.0, 1.0), (-0.70710678, 0.70710678),
    (-1.0, 0.0), (-0.70710678, -0.70710678), (0.0, -1.0), (0.70710678, -0.70710678),
]


def resize_bilinear_32_from_pil(im: Image.Image) -> tuple[np.ndarray, float]:
    """
    Match Dart bilinear sampling cleanly:
    gx = x * (w - 1) / 31.0, gy = y * (h - 1) / 31.0
    """
    im = im.convert('RGB')
    w, h = im.size
    arr = np.asarray(im, dtype=np.float32) / 255.0
    if w == 1 or h == 1:
        resized = np.asarray(im.resize((GRID_N, GRID_N), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0
    else:
        xs = np.arange(GRID_N, dtype=np.float32) * ((w - 1) / 31.0)
        ys = np.arange(GRID_N, dtype=np.float32) * ((h - 1) / 31.0)
        x0 = np.floor(xs).astype(np.int32)
        y0 = np.floor(ys).astype(np.int32)
        x1 = np.minimum(w - 1, x0 + 1)
        y1 = np.minimum(h - 1, y0 + 1)
        wx = (xs - x0)[None, :, None]
        wy = (ys - y0)[:, None, None]
        c00 = arr[y0[:, None], x0[None, :], :]
        c10 = arr[y0[:, None], x1[None, :], :]
        c01 = arr[y1[:, None], x0[None, :], :]
        c11 = arr[y1[:, None], x1[None, :], :]
        top = c00 * (1.0 - wx) + c10 * wx
        bot = c01 * (1.0 - wx) + c11 * wx
        resized = top * (1.0 - wy) + bot * wy
    aspect = float(min(w, h)) / float(max(1, max(w, h)))
    return resized.astype(np.float32), aspect


def extract_features_32x32(grid: np.ndarray, aspect_ratio: float) -> np.ndarray:
    """
    grid: (32, 32, 3) float32 in [0, 1], RGB.
    Returns (48,) float32 vector.
    """
    f = np.zeros(FEATURE_COUNT, dtype=np.float32)
    r = grid[:, :, 0]
    g = grid[:, :, 1]
    b = grid[:, :, 2]

    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / (mx + 1e-4)

    luma_mean = float(y.mean())
    luma_std = float(y.std())
    core_luma = float(y[MASK_CORE].mean())
    mid_luma = float(y[MASK_MID].mean())
    outer_luma = float(y[MASK_OUTER].mean())

    metal = (y > 0.48) & (sat < 0.26)
    spec_core = (y > 0.78) & (sat < 0.22)
    dark_core_pit = (y < 0.22) & MASK_CORE

    # Gradients & Laplacian on interior [1..30, 1..30]
    gx = np.abs(y[1:-1, 2:] - y[1:-1, :-2]) * 0.5
    gy = np.abs(y[2:, 1:-1] - y[:-2, 1:-1]) * 0.5
    grad = np.zeros_like(y)
    grad[1:-1, 1:-1] = gx + gy

    lap = np.zeros_like(y)
    lap[1:-1, 1:-1] = np.abs(
        4.0 * y[1:-1, 1:-1]
        - y[:-2, 1:-1] - y[2:, 1:-1]
        - y[1:-1, :-2] - y[1:-1, 2:]
    )

    f[0] = luma_mean
    f[1] = luma_std
    f[2] = core_luma
    f[3] = mid_luma
    f[4] = outer_luma
    f[5] = core_luma - mid_luma
    f[6] = mid_luma - outer_luma
    f[7] = float(dark_core_pit.sum()) / float(MASK_CORE.sum())
    f[8] = float((spec_core & MASK_CORE45).sum()) / float(MASK_CORE45.sum())
    f[9] = float((metal & MASK_IN65).sum()) / float(MASK_IN65.sum())
    f[10] = float((metal & MASK_OUTER).sum()) / float(MASK_OUTER.sum())

    top_m = float(metal[:3, :].mean())
    bot_m = float(metal[-3:, :].mean())
    left_m = float(metal[:, :3].mean())
    right_m = float(metal[:, -3:].mean())
    f[11] = max(top_m, bot_m, left_m, right_m)

    ysorted = np.sort(y.ravel())
    f[12] = float(ysorted[921] - ysorted[102])  # P90 - P10 on 1024 px

    q1 = float(y[:16, :16].mean())
    q2 = float(y[:16, 16:].mean())
    q3 = float(y[16:, :16].mean())
    q4 = float(y[16:, 16:].mean())
    q_arr = np.array([q1, q2, q3, q4], dtype=np.float32)
    f[13] = max(0.0, 1.0 - float(q_arr.std()) * 3.0)

    # Group B: gradients & cold texture
    f[14] = float(grad.mean())
    f[15] = float(grad[_rad <= 0.55].mean())
    metal_bright = (y > 0.35) & (sat < 0.28)
    if metal_bright.any():
        f[16] = float(lap[metal_bright].mean())
    in60_lap = np.sort(lap[MASK_IN60])
    f[17] = float(in60_lap[int(len(in60_lap) * 0.90)])
    f[18] = float(((y < (mid_luma - 0.16)) & MASK_CORE28).sum()) / float(MASK_CORE28.sum())
    f[19] = float(y[MASK_RING_DONUT].mean() - y[MASK_CENTER18].mean())

    bins = np.clip((y * 7.999).astype(np.int32), 0, 7)
    hist = np.bincount(bins.ravel(), minlength=8).astype(np.float32) / 1024.0
    nz = hist[hist > 0]
    f[20] = float(-(nz * np.log(nz)).sum() / math.log(8.0))

    f[21] = (float((y[MASK_CORE] > 0.55).mean()) + 0.01) / (float((y[MASK_MID] > 0.45).mean()) + 0.05)

    exits = int(top_m > 0.12) + int(bot_m > 0.12) + int(left_m > 0.12) + int(right_m > 0.12)
    f[22] = exits / 4.0

    cm_h = float(metal[13:19, :].mean())
    cm_v = float(metal[:, 13:19].mean())
    f[23] = max(min(top_m, bot_m) * cm_v, min(left_m, right_m) * cm_h)

    row_m = metal.mean(axis=1)
    col_m = metal.mean(axis=0)
    # Dumbbell neck ratio: mid waist dip between two thick halves
    h_ends = min(float(row_m[3:12].max()), float(row_m[20:29].max()))
    h_waist = float(row_m[12:20].min()) if h_ends > 0 else 0.0
    v_ends = min(float(col_m[3:12].max()), float(col_m[20:29].max()))
    v_waist = float(col_m[12:20].min()) if v_ends > 0 else 0.0
    f[24] = max(
        (h_ends - h_waist) if h_ends > 0.15 else 0.0,
        (v_ends - v_waist) if v_ends > 0.15 else 0.0,
    )

    y75 = y[MASK_IN75]
    ym = float(y75.mean())
    high = y75[y75 >= ym]
    low = y75[y75 < ym]
    if len(high) > 0 and len(low) > 0:
        w1 = len(high) / len(y75)
        w0 = len(low) / len(y75)
        inter = w0 * w1 * float((high.mean() - low.mean()) ** 2)
        f[25] = inter / (float(y75.var()) + 1e-4)

    # Group C: Morphometry, second moments & wire/pin rejection
    my, mx_idx = np.where(metal)
    if len(my) >= 4:
        cy = float(my.mean())
        cx = float(mx_idx.mean())
        dy_c = my.astype(np.float32) - cy
        dx_c = mx_idx.astype(np.float32) - cx
        cxx = float((dx_c * dx_c).mean())
        cyy = float((dy_c * dy_c).mean())
        cxy = float((dx_c * dy_c).mean())
        tr = cxx + cyy
        diff = math.sqrt((cxx - cyy) ** 2 + 4.0 * cxy * cxy)
        lam1 = max(1e-4, 0.5 * (tr + diff))
        lam2 = max(1e-4, 0.5 * (tr - diff))
        f[26] = (lam1 - lam2) / (lam1 + lam2)
        f[27] = math.sqrt(lam2) / 16.0
        f[28] = math.sqrt(lam1) / 16.0
        major_len = max(2.0, 2.0 * math.sqrt(lam1))
        bw = float(mx_idx.max() - mx_idx.min() + 1)
        bh = float(my.max() - my.min() + 1)
        f[30] = float(len(my)) / (bw * bh)
        f[31] = min(1.0, (4.0 * float(len(my))) / (math.pi * major_len * major_len))
    else:
        f[26] = 0.0
        f[27] = 0.0
        f[28] = 0.0
        f[30] = 0.0
        f[31] = 0.0

    # Collinear opposite-ray thin wire score along 4 axes (0, 45, 90, 135 deg)
    best_wire = 0.0
    axes_pairs = [(_RAYS[0], _RAYS[4]), (_RAYS[1], _RAYS[5]), (_RAYS[2], _RAYS[6]), (_RAYS[3], _RAYS[7])]
    ray_dists = []
    for dx_r, dy_r in _RAYS:
        dist = 0
        for step in range(1, 15):
            sx = int(round(15.5 + dx_r * step))
            sy = int(round(15.5 + dy_r * step))
            if sx < 0 or sx >= 32 or sy < 0 or sy >= 32:
                break
            if y[sy, sx] > max(0.45, luma_mean + 0.04) and sat[sy, sx] < 0.28:
                dist = step
            else:
                # Allow 1px gap then stop
                sx2 = int(round(15.5 + dx_r * (step + 1)))
                sy2 = int(round(15.5 + dy_r * (step + 1)))
                if 0 <= sx2 < 32 and 0 <= sy2 < 32 and y[sy2, sx2] > max(0.48, luma_mean + 0.05) and sat[sy2, sx2] < 0.26:
                    dist = step
                else:
                    break
        ray_dists.append(dist / 14.0)
    f[36] = min(ray_dists)
    f[37] = float(sum(ray_dists) / 8.0)

    # Opposite axes extents vs perpendicular extents
    for a_idx in range(4):
        p_idx = (a_idx + 2) % 4
        ax_ext = 0.5 * (ray_dists[a_idx] + ray_dists[a_idx + 4])
        perp_ext = 0.5 * (ray_dists[p_idx] + ray_dists[p_idx + 4])
        wire_sc = max(0.0, ax_ext - perp_ext * 1.3)
        if wire_sc > best_wire:
            best_wire = wire_sc
    f[29] = best_wire

    qm = np.array([
        float(metal[:16, :16].mean()),
        float(metal[:16, 16:].mean()),
        float(metal[16:, :16].mean()),
        float(metal[16:, 16:].mean()),
    ], dtype=np.float32)
    f[32] = float(qm.min()) / (float(qm.max()) + 0.01)
    f[33] = float(row_m.max() - np.median(row_m))
    f[34] = float(col_m.max() - np.median(col_m))
    f[35] = (float(metal[MASK_CORE45].mean()) + 0.01) / (float(metal[MASK_CORNERS].mean()) + 0.05)

    # Group D: Chromaticity, oxide, copper ring, paper/concrete
    f[38] = float(sat.mean())
    f[39] = float(sat[MASK_CORE].mean())
    f[40] = float(sat[MASK_OUTER].mean())
    f[41] = f[40] - f[39]
    # Strict amber/copper/flux tone: R > G + 0.07 AND G > B + 0.05 (prevents crimson Red PCB where B >= G!)
    warm_oxide = (r > g + 0.07) & (g > b + 0.05) & (r > b + 0.14) & MASK_IN60
    f[42] = float(warm_oxide.sum()) / float(MASK_IN60.sum())
    neutral_paper = (y > 0.65) & (grad < 0.04) & (sat < 0.14)
    f[43] = float(neutral_paper.mean())
    f[44] = float((y < 0.30).mean())
    outer_spread = (np.abs(r - g) + np.abs(g - b) + np.abs(r - b)) / 3.0
    f[45] = float(outer_spread[MASK_OUTER].mean())
    f[46] = float(aspect_ratio)
    f[47] = float(sat[MASK_MID].mean()) - f[39]

    return np.nan_to_num(f, nan=0.0, posinf=1.0, neginf=0.0)


def extract_features_from_pil(im: Image.Image) -> np.ndarray:
    grid, aspect = resize_bilinear_32_from_pil(im)
    return extract_features_32x32(grid, aspect)
