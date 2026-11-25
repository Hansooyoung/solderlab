"""
Build clean, leak-free multi-source dataset for Soldy AI v6 (SolderLab).
7 classes:
  0: PASS_NORMAL      (Clean conical/concave THT & SMD fillets)
  1: D1_BRIDGE        (Solder bridges shorting adjacent pads/pins)
  2: D2_COLD          (Cold / dull / disturbed / charred / oxidized solder joints)
  3: D3_INSUFFICIENT  (Insufficient / starved / hollow open hole / dewetting)
  4: D4_EXCESS        (Excessive / bulbous overfilled solder blobs)
  5: D5_PINHOLE       (Pinholes / blowholes / voids in solder)
  6: NON_SOLDER       (Uncut component wire leads, component bodies, missing/shifted parts,
                       bare PCB traces, concrete table, white paper, plastic, scratches)

Zero-leakage rules:
  - ParsaVictor uses official train/val+test splits; synthetic/corrupted `zurab` and `cv` prefixes excluded.
  - Zhouyongbing splits 80/20 by board file.
  - IEEE and AndyLiu deduplicate by trimmed-content SHA-256 and split 80/20 (IEEE) or 85/15 (AndyLiu).
  - Source-grouped train/validation splits with SHA-256 content deduplication.
  - Optional work-in-progress negative directories (SOLDERLAB_WIP_PHOTOS) kept cleanly out of validation.
"""

import os
import io
import csv
import glob
import math
import hashlib
import random
from collections import Counter
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DS_ROOT = os.environ.get('SOLDERLAB_DATASET_ROOT', os.path.join(os.path.dirname(__file__), 'datasets'))
OUT_ROOT = os.path.join(DS_ROOT, 'curated_v6')
SCRATCH_ROOT = os.path.join(os.path.dirname(__file__), 'scratch')
os.makedirs(SCRATCH_ROOT, exist_ok=True)

CLASSES = [
    '0_PASS_NORMAL',
    '1_D1_BRIDGE',
    '2_D2_COLD',
    '3_D3_INSUFFICIENT',
    '4_D4_EXCESS',
    '5_D5_PINHOLE',
    '6_NON_SOLDER',
]

random.seed(42)
np.random.seed(42)


def ensure_dirs():
    for sp in ['train', 'val']:
        for cl in CLASSES:
            os.makedirs(os.path.join(OUT_ROOT, sp, cl), exist_ok=True)
    os.makedirs(SCRATCH_ROOT, exist_ok=True)


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def is_valid_crop(im: Image.Image, min_side: int = 16, max_black_frac: float = 0.25) -> bool:
    w, h = im.size
    if w < min_side or h < min_side:
        return False
    arr = np.asarray(im, dtype=np.uint8)
    if arr.ndim != 3 or arr.shape[2] < 3:
        return False
    mx = arr[:, :, :3].max(axis=2)
    black_frac = float((mx < 8).mean())
    if black_frac > max_black_frac:
        return False
    if float(arr[:, :, :3].std()) < 5.0:
        return False
    return True


def trim_black_canvas(im: Image.Image, thresh: int = 10, pad: int = 3) -> Image.Image:
    arr = np.asarray(im, dtype=np.uint8)
    m = arr[:, :, :3].max(axis=2) > thresh
    ys, xs = np.where(m)
    if len(ys) < 16:
        return im
    y1 = max(0, int(ys.min()) - pad)
    x1 = max(0, int(xs.min()) - pad)
    y2 = min(arr.shape[0], int(ys.max()) + 1 + pad)
    x2 = min(arr.shape[1], int(xs.max()) + 1 + pad)
    return im.crop((x1, y1, x2, y2))


def crop_yolo_box(im: Image.Image, cx: float, cy: float, bw: float, bh: float, pad: float = 1.20):
    iw, ih = im.size
    x1 = max(0, int((cx - bw * pad / 2.0) * iw))
    y1 = max(0, int((cy - bh * pad / 2.0) * ih))
    x2 = min(iw, int((cx + bw * pad / 2.0) * iw))
    y2 = min(ih, int((cy + bh * pad / 2.0) * ih))
    if x2 - x1 < 18 or y2 - y1 < 18:
        return None
    return im.crop((x1, y1, x2, y2))


class Collector:
    def __init__(self):
        self.seen_hashes = set()
        self.rows = []
        self.counts = Counter()

    def add(self, split: str, cls_id: int, source: str, im: Image.Image, prefix: str, check_black: bool = True) -> bool:
        if im is None:
            return False
        im = im.convert('RGB')
        min_s = 16 if source == 'ieee' else 20
        if not is_valid_crop(im, min_side=min_s, max_black_frac=0.25 if check_black else 0.99):
            return False
        # Standardize large outliers down to max 160px on long side to keep disk I/O fast
        w, h = im.size
        if max(w, h) > 160:
            s = 160.0 / max(w, h)
            im = im.resize((max(16, int(w * s)), max(16, int(h * s))), Image.Resampling.BILINEAR)
        buf = io.BytesIO()
        im.save(buf, format='PNG')
        raw = buf.getvalue()
        hsh = sha256_bytes(raw)
        if hsh in self.seen_hashes:
            return False
        self.seen_hashes.add(hsh)
        cls_name = CLASSES[cls_id]
        idx = self.counts[(split, cls_name)]
        fn = f'{prefix}_{hsh[:12]}_{idx:05d}.png'
        out_path = os.path.join(OUT_ROOT, split, cls_name, fn)
        with open(out_path, 'wb') as f:
            f.write(raw)
        self.counts[(split, cls_name)] += 1
        self.rows.append((out_path, split, cls_id, cls_name, source))
        return True


def collect_ieee(col: Collector):
    base = os.path.join(DS_ROOT, 'opensource', 'solder-joint-dataset')
    mapping = {
        'normal': 0,
        'short': 1,
        'insufficient_solder': 3,
        'excessive_solder': 4,
        'shifted_component': 6,
    }
    for folder, cid in mapping.items():
        d = os.path.join(base, folder)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.lower().endswith(('.png', '.jpg', '.jpeg', '.tif', '.tiff')):
                continue
            p = os.path.join(d, fn)
            with open(p, 'rb') as f:
                h_int = int(hashlib.md5(f.read()).hexdigest()[:8], 16)
            split = 'val' if (h_int % 5 == 0) else 'train'
            try:
                im = Image.open(p).convert('RGB')
                col.add(split, cid, 'ieee', im, f'ieee_{folder[:4]}', check_black=False)
            except Exception:
                pass


def collect_parsavictor(col: Collector):
    p_base = os.path.join(DS_ROOT, 'opensource', 'parsavictor_pcb_solder', 'final_solder')
    # class ids: 0:insuf, 1:excess, 2:bridge, 3:void, 4:missing, 5:shifted, 6:burn, 7:damage, 8:oxidation
    for official_split, out_split in [('train', 'train'), ('val', 'val'), ('test', 'val')]:
        lbl_dir = os.path.join(p_base, 'labels', official_split)
        img_dir = os.path.join(p_base, 'images', official_split)
        if not os.path.isdir(lbl_dir):
            continue
        bg_budget = 1600 if out_split == 'train' else 320
        bg_taken = 0
        for lf in sorted(os.listdir(lbl_dir)):
            if not lf.endswith('.txt'):
                continue
            pref = lf.split('_')[0]
            if pref in ('zurab', 'cv'):
                continue
            ip = os.path.join(img_dir, lf[:-4] + '.jpg')
            if not os.path.exists(ip):
                continue
            try:
                im = Image.open(ip).convert('RGB')
            except Exception:
                continue
            iw, ih = im.size
            boxes_px = []
            lines = open(os.path.join(lbl_dir, lf), 'r', encoding='utf-8').read().splitlines()
            for line in lines:
                parts = line.strip().split()
                if len(parts) != 5:
                    continue
                yc = int(parts[0])
                cx, cy, bw, bh = map(float, parts[1:])
                boxes_px.append(((cx - bw / 2) * iw, (cy - bh / 2) * ih, (cx + bw / 2) * iw, (cy + bh / 2) * ih))
                cid = None
                if yc == 0:
                    cid = 3  # D3_INSUFFICIENT
                elif yc == 1:
                    cid = 4  # D4_EXCESS
                elif yc == 2:
                    cid = 1  # D1_BRIDGE
                elif yc == 3:
                    cid = 5  # D5_PINHOLE
                elif yc in (4, 5):
                    cid = 6  # NON_SOLDER (missing / shifted component)
                elif yc == 7 and pref in ('sssssc', 'vattipalli'):
                    cid = 6  # NON_SOLDER (scratch / board damage)
                elif yc == 6 and pref in ('vattipalli', 'numeric123'):
                    cid = 2  # D2_COLD (charred/disturbed dark oxidized joint)
                elif yc == 8 and pref == 'vattipalli':
                    cid = 2  # D2_COLD (oxidized dull joint)
                if cid is None:
                    continue
                cr = crop_yolo_box(im, cx, cy, bw, bh, pad=1.18)
                if cr is not None:
                    col.add(out_split, cid, f'pv_{pref}', cr, f'pv_{pref[:4]}')

            # Sample clean non-solder PCB background / traces away from all boxes
            if bg_taken < bg_budget and iw >= 160 and ih >= 160:
                for _ in range(3):
                    if bg_taken >= bg_budget:
                        break
                    sz = random.choice([48, 64, 80])
                    if iw <= sz + 8 or ih <= sz + 8:
                        continue
                    x1 = random.randint(4, iw - sz - 4)
                    y1 = random.randint(4, ih - sz - 4)
                    x2, y2 = x1 + sz, y1 + sz
                    overlaps = any(
                        not (x2 < bx1 or x1 > bx2 or y2 < by1 or y1 > by2)
                        for (bx1, by1, bx2, by2) in boxes_px
                    )
                    if overlaps:
                        continue
                    cr = im.crop((x1, y1, x2, y2))
                    if col.add(out_split, 6, f'pv_bg_{pref}', cr, f'pvbg_{pref[:4]}'):
                        bg_taken += 1


def collect_zhouyongbing(col: Collector):
    base = os.path.join(DS_ROOT, 'opensource', 'zhouyongbing_pcb_solder')
    # 0: excess(D4), 1: bridge(D1), 2: normal(PASS), 3: insufficient(D3), 4: dull/cold(D2)
    zmap = {0: 4, 1: 1, 2: 0, 3: 3, 4: 2}
    imgs = sorted(glob.glob(os.path.join(base, 'images', '*.jpg')))
    for idx, ip in enumerate(imgs):
        lp = os.path.join(base, 'labels', os.path.basename(ip)[:-4] + '.txt')
        if not os.path.exists(lp):
            continue
        split = 'val' if (idx % 5 == 0) else 'train'
        im = Image.open(ip).convert('RGB')
        for line in open(lp, 'r'):
            p = line.strip().split()
            if len(p) != 5:
                continue
            yc = int(p[0])
            cid = zmap.get(yc)
            if cid is None:
                continue
            cx, cy, bw, bh = map(float, p[1:])
            cr = crop_yolo_box(im, cx, cy, bw, bh, pad=1.15)
            # Keep rare classes (3,4) strictly separated too (or split=train for singletons)
            use_sp = 'train' if yc in (3, 4) else split
            if cr is not None:
                col.add(use_sp, cid, 'zhouyongbing', cr, f'zhou_c{yc}')


def collect_andyliu(col: Collector):
    pq_dir = os.path.join(DS_ROOT, 'opensource', 'andyliu_solder')
    # 1. Trimmed single-joint datasets
    for pq_name in ['pad_1016.parquet', 'unsolder_1004.parquet']:
        pq_path = os.path.join(pq_dir, pq_name)
        if not os.path.exists(pq_path):
            continue
        df = pd.read_parquet(pq_path)
        for row_i, row in df.iterrows():
            txt = str(row['text']).lower()
            raw = row['image']
            b = raw['bytes'] if isinstance(raw, dict) else raw
            try:
                im = Image.open(io.BytesIO(b)).convert('RGB')
            except Exception:
                continue
            im = trim_black_canvas(im, thresh=10, pad=2)
            w, h = im.size
            if min(w, h) < 22:
                continue
            # Determine class carefully
            if 'bridge' in txt and 'insufficient' not in txt:
                cid = 1  # D1_BRIDGE
            elif 'excess' in txt:
                cid = 4  # D4_EXCESS
            elif 'empty' in txt or 'insufficient' in txt:
                cid = 3  # D3_INSUFFICIENT
            elif 'hole' in txt:
                cid = 5  # D5_PINHOLE
            elif 'appearance less' in txt:
                cid = 2  # D2_COLD (rough / matte grainy surface defect)
            else:
                continue
            h_int = int(hashlib.sha256(b).hexdigest()[:8], 16)
            split = 'val' if (h_int % 20 < 3) else 'train'
            col.add(split, cid, f'andyliu_{pq_name[:4]}', im, f'andy_{pq_name[:3]}')

    # 2. Full-board V3 strict 'no defect' & 'normal' -> extract crisp THT PASS_NORMAL fillets via whiteFloor
    v3_path = os.path.join(pq_dir, 'v3_full.parquet')
    if os.path.exists(v3_path):
        v3 = pd.read_parquet(v3_path)
        nd = v3[v3['text'].str.lower().str.contains('no defect')]
        for idx, row in nd.iterrows():
            raw = row['image']
            b = raw['bytes'] if isinstance(raw, dict) else raw
            try:
                im = Image.open(io.BytesIO(b)).convert('RGB')
            except Exception:
                continue
            im = trim_black_canvas(im, thresh=10, pad=0)
            arr = np.asarray(im, dtype=np.float32)
            ih, iw = arr.shape[:2]
            if min(iw, ih) < 120:
                continue
            h_int = int(hashlib.sha256(b).hexdigest()[:8], 16)
            split = 'val' if (h_int % 7 == 0) else 'train'
            luma = 0.2126 * arr[:, :, 0] + 0.7152 * arr[:, :, 1] + 0.0722 * arr[:, :, 2]
            wf = arr.min(axis=2)
            sat = (arr.max(axis=2) - arr.min(axis=2)) / (arr.max(axis=2) + 1.0)
            # Detect compact metallic peaks (not thin silkscreen text) on clean no-defect boards
            cand = (luma > 108) & (wf > 72) & (sat < 0.28)
            step = 6
            taken = []
            for y in range(18, ih - 18, step):
                for x in range(18, iw - 18, step):
                    if luma[y, x] < 120 or wf[y, x] < 80 or sat[y, x] > 0.26:
                        continue
                    win = luma[y - 8 : y + 9, x - 8 : x + 9]
                    if luma[y, x] < win.max() - 3.0:
                        continue
                    core_m = cand[y - 5 : y + 6, x - 5 : x + 6].mean()
                    outer_m = cand[y - 16 : y + 17, x - 16 : x + 17].mean()
                    if core_m < 0.30 or outer_m > 0.58 or outer_m < 0.06:
                        continue
                    if any((x - tx) ** 2 + (y - ty) ** 2 < 28 ** 2 for tx, ty in taken):
                        continue
                    taken.append((x, y))
                    half = 24
                    x1, y1 = max(0, x - half), max(0, y - half)
                    x2, y2 = min(iw, x + half), min(ih, y + half)
                    if x2 - x1 >= 32 and y2 - y1 >= 32:
                        col.add(split, 0, 'andyliu_v3_nd', im.crop((x1, y1, x2, y2)), 'v3nd')
                    if len(taken) >= 36:
                        break
                if len(taken) >= 36:
                    break


def collect_wip_hard_negatives(col: Collector):
    """
    Optional hard-negative mining from empirical patches and user-supplied WIP PCB photos
    containing uncut component wire leads (set SOLDERLAB_WIP_PHOTOS env var to enable).
    """
    emp_train = os.path.join(DS_ROOT, 'empirical_patches', 'train')
    emp_map = {'PASS_NORMAL': 0, 'D2_COLD': 2, 'D3_INSUFFICIENT': 3, 'D4_EXCESS': 4}
    for cname, cid in emp_map.items():
        cdir = os.path.join(emp_train, cname)
        if not os.path.isdir(cdir):
            continue
        for fn in sorted(os.listdir(cdir)):
            p = os.path.join(cdir, fn)
            im = Image.open(p).convert('RGB')
            arr = np.asarray(im, dtype=np.float32)
            # Must have genuine saturated red PCB background >= 22% pixels (rejects paper, plastic, grey bench!)
            red_pcb = (arr[:, :, 0] > 95) & ((arr[:, :, 0] - arr[:, :, 1]) > 35) & ((arr[:, :, 0] - arr[:, :, 2]) > 25)
            if float(red_pcb.mean()) < 0.22:
                continue
            h, w = arr.shape[:2]
            cx1, cx2 = int(w * 0.22), int(w * 0.78)
            cy1, cy2 = int(h * 0.22), int(h * 0.78)
            core = arr[cy1:cy2, cx1:cx2]
            luma = 0.2126 * core[:, :, 0] + 0.7152 * core[:, :, 1] + 0.0722 * core[:, :, 2]
            sat = (core.max(axis=2) - core.min(axis=2)) / (core.max(axis=2) + 1.0)
            metal = (luma > 130) & (sat < 0.28)
            metal_frac = float(metal.mean())
            if metal_frac < 0.08:
                continue
            top_hit = metal[:3, :].any()
            bot_hit = metal[-3:, :].any()
            left_hit = metal[:, :3].any()
            right_hit = metal[:, -3:].any()
            border_sides = int(top_hit) + int(bot_hit) + int(left_hit) + int(right_hit)
            if border_sides >= 2 and metal_frac < 0.24 and cname != 'D3_INSUFFICIENT':
                col.add('train', 6, 'emp_uncut_lead', im, 'emplead')
            else:
                col.add('train', cid, 'emp_clean_tht', im, 'emp')

    # 2. Hard Negative Mining from optional WIP / uncut-lead photos
    wip_root = os.environ.get('SOLDERLAB_WIP_PHOTOS', '').strip()
    proses_imgs = sorted(set(glob.glob(os.path.join(wip_root, '**', '*.jpg'), recursive=True))) if wip_root and os.path.isdir(wip_root) else []

    for ip in proses_imgs:
        try:
            im = Image.open(ip).convert('RGB')
        except Exception:
            continue
        w, h = im.size
        sc = 1000.0 / max(w, h)
        sm = im.resize((int(w * sc), int(h * sc)), Image.Resampling.BILINEAR)
        arr = np.asarray(sm, dtype=np.float32)
        nh, nw = arr.shape[:2]
        luma = 0.2126 * arr[:, :, 0] + 0.7152 * arr[:, :, 1] + 0.0722 * arr[:, :, 2]
        sat = (arr.max(axis=2) - arr.min(axis=2)) / (arr.max(axis=2) + 1.0)
        # Find red PCB mask -> crop long bright thin wire pins (uncut component leads!)
        # Explicitly verify horizontal/vertical minor thickness vs elongated wire ridge so we never label pads as wire!
        red_pcb = (arr[:, :, 0] > 95) & ((arr[:, :, 0] - arr[:, :, 1]) > 35)
        ry, rx = np.where(red_pcb)
        if len(ry) >= 150:
            y_min, y_max = max(32, int(np.percentile(ry, 5))), min(nh - 32, int(np.percentile(ry, 95)))
            x_min, x_max = max(32, int(np.percentile(rx, 5))), min(nw - 32, int(np.percentile(rx, 95)))
            wire_taken = 0
            for _ in range(180):
                if wire_taken >= 18 or x_max <= x_min + 10 or y_max <= y_min + 10:
                    break
                px = random.randint(x_min, x_max)
                py = random.randint(y_min, y_max)
                if luma[py, px] > 155 and sat[py, px] < 0.30:
                    half = random.choice([20, 24, 30])
                    cr_arr = arr[max(0, py - half) : min(nh, py + half), max(0, px - half) : min(nw, px + half)]
                    if cr_arr.shape[0] < 24 or cr_arr.shape[1] < 24:
                        continue
                    c_l = 0.2126 * cr_arr[:, :, 0] + 0.7152 * cr_arr[:, :, 1] + 0.0722 * cr_arr[:, :, 2]
                    c_s = (cr_arr.max(axis=2) - cr_arr.min(axis=2)) / (cr_arr.max(axis=2) + 1.0)
                    c_m = (c_l > 145) & (c_s < 0.30)
                    mf = float(c_m.mean())
                    # Verify it's a thin elongated ridge (6%..28% bright metal, touching 2+ edges or thin aspect)
                    if 0.05 <= mf <= 0.28:
                        ys_m, xs_m = np.where(c_m)
                        if len(ys_m) >= 8:
                            cxx = float(((xs_m - xs_m.mean()) ** 2).mean())
                            cyy = float(((ys_m - ys_m.mean()) ** 2).mean())
                            cxy = float(((xs_m - xs_m.mean()) * (ys_m - ys_m.mean())).mean())
                            tr = cxx + cyy
                            df = math.sqrt((cxx - cyy) ** 2 + 4 * cxy * cxy)
                            aniso = df / max(1e-4, tr)
                            if aniso >= 0.55:
                                cr = sm.crop((max(0, px - half), max(0, py - half), min(nw, px + half), min(nh, py + half)))
                                if col.add('train', 6, 'proses_uncut_lead', cr, 'prolead'):
                                    wire_taken += 1
        # Also pick concrete bench, white paper, skin/bag background patches strictly off-PCB
        taken_bg = 0
        for _ in range(25):
            if taken_bg >= 8:
                break
            half = random.choice([28, 36, 48])
            px = random.randint(half + 10, nw - half - 10)
            py = random.randint(half + 10, nh - half - 10)
            sub = red_pcb[py - half : py + half, px - half : px + half]
            if float(sub.mean()) > 0.03:
                continue
            cr = sm.crop((px - half, py - half, px + half, py + half))
            if col.add('train', 6, 'proses_bg', cr, 'probg'):
                taken_bg += 1


def build_contact_sheet(split: str, out_file: str):
    rows_imgs = []
    for cid, cname in enumerate(CLASSES):
        d = os.path.join(OUT_ROOT, split, cname)
        files = sorted(os.listdir(d))
        picks = random.sample(files, min(8, len(files))) if files else []
        rows_imgs.append((f'{cname}\n(n={len(files)})', [os.path.join(d, f) for f in picks]))
    mont = Image.new('RGB', (170 + 8 * 84, len(CLASSES) * 84), (18, 18, 18))
    draw = ImageDraw.Draw(mont)
    for ri, (lbl, paths) in enumerate(rows_imgs):
        draw.text((8, ri * 84 + 28), lbl, fill=(240, 240, 240))
        for ci, p in enumerate(paths):
            im = Image.open(p).convert('RGB').resize((80, 80))
            mont.paste(im, (170 + ci * 84 + 2, ri * 84 + 2))
    mont.save(out_file)


def main():
    ensure_dirs()
    # Wipe existing files in curated_v6 cleanly before rebuilding (python script owns curated_v6 only)
    for sp in ['train', 'val']:
        for cl in CLASSES:
            d = os.path.join(OUT_ROOT, sp, cl)
            for f in os.listdir(d):
                os.remove(os.path.join(d, f))

    col = Collector()
    print('Collecting IEEE SMD...')
    collect_ieee(col)
    print('Collecting ParsaVictor...')
    collect_parsavictor(col)
    print('Collecting Zhouyongbing THT...')
    collect_zhouyongbing(col)
    print('Collecting AndyLiu0104 THT & V3 Normal...')
    collect_andyliu(col)
    print('Collecting WIP Uncut Leads & Empirical THT...')
    collect_wip_hard_negatives(col)

    manifest_path = os.path.join(OUT_ROOT, 'manifest.csv')
    with open(manifest_path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['path', 'split', 'class_id', 'class_name', 'source'])
        w.writerows(col.rows)

    print('\n=== CURATED V6 SUMMARY ===')
    for sp in ['train', 'val']:
        tot = sum(col.counts[(sp, c)] for c in CLASSES)
        print(f'Split {sp.upper()}: total={tot}')
        for c in CLASSES:
            print(f'  {c:20s}: {col.counts[(sp, c)]:5d}')

    print('\n=== SOURCE BREAKDOWN ===')
    src_cnt = Counter((r[1], r[3], r[4]) for r in col.rows)
    for (sp, cname, src), cnt in sorted(src_cnt.items()):
        print(f'  {sp:5s} | {cname:18s} | {src:18s}: {cnt}')

    build_contact_sheet('train', os.path.join(SCRATCH_ROOT, 'curated_v6_train_grid.png'))
    build_contact_sheet('val', os.path.join(SCRATCH_ROOT, 'curated_v6_val_grid.png'))
    print('Saved verification grids to scratch!')


if __name__ == '__main__':
    main()
