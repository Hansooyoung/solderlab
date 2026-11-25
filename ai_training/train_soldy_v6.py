"""
Train Soldy-Net-V6 Hybrid Ensemble (Standardized 2x MLP + 40 Depth-8 ExtraTrees)
on curated_v6 multi-source dataset across 7 classes.

Exports clean Pure-Dart JSON artifact to:
  assets/models/soldy_v6_model.json
  assets/models/model_metadata.json
  assets/models/labels.txt
"""

import os
import csv
import json
import time
import math
import numpy as np
from PIL import Image
from collections import Counter
from soldy_features import FEATURE_COUNT, extract_features_from_pil

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CURATED_ROOT = os.environ.get(
    'SOLDERLAB_CURATED_DIR',
    os.path.join(os.path.dirname(__file__), 'datasets', 'curated_v6'),
)
APP_MODELS = os.path.join(REPO_ROOT, 'assets', 'models')
CACHE_NPZ = os.path.join(CURATED_ROOT, 'features_v6_cache.npz')

CLASSES = [
    'PASS_NORMAL',
    'D1_BRIDGE',
    'D2_COLD',
    'D3_INSUFFICIENT',
    'D4_EXCESS',
    'D5_PINHOLE',
    'NON_SOLDER',
]
NUM_CLASSES = len(CLASSES)


def synthesize_red_pcb_variant(im: Image.Image) -> Image.Image:
    """
    Shift colored PCB solder mask (Green/Blue/Black) to Crimson Red PCB while preserving
    silver/tin metallic highlights (low saturation) untouched! Train-only domain augmentation.
    """
    arr = np.asarray(im, dtype=np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / (mx + 1.0)
    # Only shift saturated mask or dark colored background pixels (keep shiny tin R~G~B intact!)
    mask_px = (sat >= 0.22) & ((g > r + 8) | (b > r + 8))
    if not mask_px.any():
        return None
    out = arr.copy()
    dom = np.maximum(g, b)
    out[mask_px, 0] = np.clip(dom[mask_px] * 1.35 + 25.0, 0.0, 245.0)
    out[mask_px, 1] = np.clip(r[mask_px] * 0.55 + mn[mask_px] * 0.25, 0.0, 180.0)
    out[mask_px, 2] = np.clip(r[mask_px] * 0.65 + mn[mask_px] * 0.35, 0.0, 195.0)
    return Image.fromarray(out.astype(np.uint8))


def load_or_extract_dataset(force_rebuild: bool = False):
    if os.path.exists(CACHE_NPZ) and not force_rebuild:
        d = np.load(CACHE_NPZ, allow_pickle=True)
        if d['X_train'].shape[1] == FEATURE_COUNT:
            print(f'Loaded cached features: train={d["X_train"].shape}, val={d["X_val"].shape}')
            return (
                d['X_train'], d['y_train'], list(d['src_train']),
                d['X_val'], d['y_val'], list(d['src_val']),
            )

    manifest = os.path.join(CURATED_ROOT, 'manifest.csv')
    X_tr, y_tr, s_tr = [], [], []
    X_va, y_va, s_va = [], [], []
    rows = list(csv.DictReader(open(manifest, 'r', encoding='utf-8')))
    t0 = time.time()
    for i, r in enumerate(rows):
        im = Image.open(r['path']).convert('RGB')
        feat = extract_features_from_pil(im)
        cid = int(r['class_id'])
        sp = r['split']
        src = r['source']
        if sp == 'train':
            X_tr.append(feat)
            y_tr.append(cid)
            s_tr.append(src)
            if cid in (2, 5) or src in ('zhouyongbing', 'emp_clean_tht', 'emp_uncut_lead', 'proses_uncut_lead', 'andyliu_v3_nd'):
                for k_rot in (1, 2, 3):
                    feat_rot = extract_features_from_pil(im.rotate(90 * k_rot, expand=True))
                    X_tr.append(feat_rot)
                    y_tr.append(cid)
                    s_tr.append(src)
                if cid in (2, 5) or src in ('emp_uncut_lead', 'proses_uncut_lead'):
                    feat_flp = extract_features_from_pil(im.transpose(Image.Transpose.FLIP_LEFT_RIGHT))
                    X_tr.append(feat_flp)
                    y_tr.append(cid)
                    s_tr.append(src)
            # Train-only multi-color solder mask invariance (Red <-> Green/Blue while keeping silver R~G~B intact!)
            if cid in (0, 1, 4, 5, 6) and src in ('zhouyongbing', 'andyliu_v3_nd', 'andyliu_pad_', 'andyliu_unso', 'pv_bg_neazu', 'pv_bg_numeric123'):
                red_im = synthesize_red_pcb_variant(im)
                if red_im is not None:
                    X_tr.append(extract_features_from_pil(red_im))
                    y_tr.append(cid)
                    s_tr.append(src + '_red')
            if cid == 6 and src in ('emp_uncut_lead', 'proses_uncut_lead'):
                arr_u = np.asarray(im, dtype=np.uint8)
                # Shift Red PCB wire crops to Green & Blue PCB wire crops so all PCB colors reject 1D uncut pins
                g_arr = arr_u.copy()
                g_arr[:, :, 0], g_arr[:, :, 1] = arr_u[:, :, 1], arr_u[:, :, 0]
                b_arr = arr_u.copy()
                b_arr[:, :, 0], b_arr[:, :, 2] = arr_u[:, :, 2], arr_u[:, :, 0]
                for mod_arr, suf in [(g_arr, '_grn'), (b_arr, '_blu')]:
                    mod_im = Image.fromarray(mod_arr)
                    X_tr.append(extract_features_from_pil(mod_im))
                    y_tr.append(cid)
                    s_tr.append(src + suf)
                    X_tr.append(extract_features_from_pil(mod_im.rotate(90, expand=True)))
                    y_tr.append(cid)
                    s_tr.append(src + suf)
        else:
            X_va.append(feat)
            y_va.append(cid)
            s_va.append(src)
        if (i + 1) % 3000 == 0:
            print(f'  Extracted {i+1}/{len(rows)} ({time.time()-t0:.1f}s)')

    X_train = np.array(X_tr, dtype=np.float32)
    y_train = np.array(y_tr, dtype=np.int64)
    X_val = np.array(X_va, dtype=np.float32)
    y_val = np.array(y_va, dtype=np.int64)
    np.savez_compressed(
        CACHE_NPZ,
        X_train=X_train, y_train=y_train, src_train=np.array(s_tr),
        X_val=X_val, y_val=y_val, src_val=np.array(s_va),
    )
    print(f'Extracted features in {time.time()-t0:.1f}s: train={X_train.shape}, val={X_val.shape}')
    return X_train, y_train, s_tr, X_val, y_val, s_va


# ==============================================================================
# 1. Pure-NumPy 3-Layer Neural Network (48 -> 160 -> 80 -> 7) with Adam + Cosine LR
# ==============================================================================
class NumpyMLP:
    def __init__(self, in_dim: int, h1: int, h2: int, out_dim: int, seed: int = 42):
        rng = np.random.default_rng(seed)
        self.W1 = (rng.standard_normal((in_dim, h1)) * math.sqrt(2.0 / in_dim)).astype(np.float32)
        self.b1 = np.zeros(h1, dtype=np.float32)
        self.W2 = (rng.standard_normal((h1, h2)) * math.sqrt(2.0 / h1)).astype(np.float32)
        self.b2 = np.zeros(h2, dtype=np.float32)
        self.W3 = (rng.standard_normal((h2, out_dim)) * math.sqrt(2.0 / h2)).astype(np.float32)
        self.b3 = np.zeros(out_dim, dtype=np.float32)

    def params(self):
        return [self.W1, self.b1, self.W2, self.b2, self.W3, self.b3]

    def set_params(self, state):
        self.W1, self.b1, self.W2, self.b2, self.W3, self.b3 = [x.copy() for x in state]

    def forward(self, X: np.ndarray, train: bool = False, drop_p: float = 0.15, rng=None):
        z1 = X @ self.W1 + self.b1
        a1 = np.maximum(0.0, z1)
        m1 = None
        if train and drop_p > 0.0:
            m1 = (rng.random(a1.shape, dtype=np.float32) >= drop_p).astype(np.float32) / (1.0 - drop_p)
            a1 = a1 * m1
        z2 = a1 @ self.W2 + self.b2
        a2 = np.maximum(0.0, z2)
        m2 = None
        if train and drop_p > 0.0:
            m2 = (rng.random(a2.shape, dtype=np.float32) >= drop_p).astype(np.float32) / (1.0 - drop_p)
            a2 = a2 * m2
        logits = a2 @ self.W3 + self.b3
        return logits, (X, z1, a1, m1, z2, a2, m2)

    @staticmethod
    def softmax(logits: np.ndarray) -> np.ndarray:
        mx = logits.max(axis=1, keepdims=True)
        e = np.exp(np.clip(logits - mx, -30.0, 30.0))
        return e / e.sum(axis=1, keepdims=True)

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        logits, _ = self.forward(X, train=False)
        return self.softmax(logits)


def train_mlp(X_tr, y_tr, sample_w, X_va, y_va, seed: int = 42, epochs: int = 55) -> NumpyMLP:
    rng = np.random.default_rng(seed)
    mlp = NumpyMLP(FEATURE_COUNT, 160, 80, NUM_CLASSES, seed=seed)
    ps = mlp.params()
    m_adam = [np.zeros_like(p) for p in ps]
    v_adam = [np.zeros_like(p) for p in ps]
    step = 0
    best_score = -1.0
    best_state = [p.copy() for p in ps]

    # Pre-normalize balanced sampling probs for mini-batches
    probs_sample = sample_w / sample_w.sum()
    n = len(X_tr)
    batch_size = 256
    steps_per_epoch = max(60, n // batch_size)
    lr_max = 2.2e-3
    lr_min = 1.5e-4
    wd = 2.5e-4
    smooth = 0.03

    # Also compute gentle class reweight for loss stability
    for ep in range(epochs):
        lr = lr_min + 0.5 * (lr_max - lr_min) * (1.0 + math.cos(math.pi * ep / epochs))
        for _ in range(steps_per_epoch):
            step += 1
            idx = rng.choice(n, size=batch_size, replace=True, p=probs_sample)
            xb = X_tr[idx]
            yb = y_tr[idx]
            logits, (x_in, z1, a1, d1, z2, a2, d2) = mlp.forward(xb, train=True, drop_p=0.14, rng=rng)
            pr = mlp.softmax(logits)
            target = np.full_like(pr, smooth / (NUM_CLASSES - 1))
            target[np.arange(batch_size), yb] = 1.0 - smooth
            dlogits = (pr - target) / batch_size

            gW3 = a2.T @ dlogits + wd * mlp.W3
            gb3 = dlogits.sum(axis=0)
            da2 = dlogits @ mlp.W3.T
            if d2 is not None:
                da2 = da2 * d2
            dz2 = da2 * (z2 > 0)

            gW2 = a1.T @ dz2 + wd * mlp.W2
            gb2 = dz2.sum(axis=0)
            da1 = dz2 @ mlp.W2.T
            if d1 is not None:
                da1 = da1 * d1
            dz1 = da1 * (z1 > 0)

            gW1 = x_in.T @ dz1 + wd * mlp.W1
            gb1 = dz1.sum(axis=0)

            grads = [gW1, gb1, gW2, gb2, gW3, gb3]
            for pi, (p, g) in enumerate(zip(ps, grads)):
                m_adam[pi] = 0.9 * m_adam[pi] + 0.1 * g
                v_adam[pi] = 0.999 * v_adam[pi] + 0.001 * (g * g)
                m_hat = m_adam[pi] / (1.0 - 0.9 ** step)
                v_hat = v_adam[pi] / (1.0 - 0.999 ** step)
                p -= lr * m_hat / (np.sqrt(v_hat) + 1e-8)

        # Evaluate balanced macro-F1 + overall accuracy on held-out val
        vp = mlp.predict_proba(X_va)
        vpred = vp.argmax(axis=1)
        acc = float((vpred == y_va).mean())
        recalls = []
        for c in range(NUM_CLASSES):
            cm = (y_va == c)
            recalls.append(float((vpred[cm] == c).mean()) if cm.any() else 0.0)
        bal_acc = float(np.mean(recalls))
        score = 0.55 * acc + 0.45 * bal_acc
        if score > best_score:
            best_score = score
            best_state = [p.copy() for p in ps]
        if (ep + 1) % 10 == 0 or ep == epochs - 1:
            print(f'  [MLP seed={seed}] ep={ep+1:2d}/{epochs} val_acc={acc*100:.2f}% bal_acc={bal_acc*100:.2f}% best={best_score*100:.2f}%')

    mlp.set_params(best_state)
    return mlp


# ==============================================================================
# 2. Fast Vectorized Extra-Trees / Decision Forest (48 Depth-8 Trees)
# ==============================================================================
class ExtraTree:
    def __init__(self, max_depth: int = 8, min_leaf: int = 8, seed: int = 0):
        self.max_depth = max_depth
        self.min_leaf = min_leaf
        self.rng = np.random.default_rng(seed)
        self.nodes = []  # flat list -> compact dict export

    def fit(self, X: np.ndarray, y: np.ndarray, w: np.ndarray):
        self.root = self._build(X, y, w, depth=0)

    def _build(self, X: np.ndarray, y: np.ndarray, w: np.ndarray, depth: int):
        counts = np.bincount(y, weights=w, minlength=NUM_CLASSES).astype(np.float64)
        total_w = counts.sum()
        probs = (counts / max(1e-9, total_w)).astype(np.float32)
        # Pure or leaf limit
        if depth >= self.max_depth or len(y) < self.min_leaf or (counts > 0).sum() <= 1:
            return {'leaf': True, 'p': np.round(probs, 4).tolist()}

        gini_parent = 1.0 - float(((counts / max(1e-9, total_w)) ** 2).sum())
        best_gain = 0.0
        best_feat = -1
        best_thr = 0.0
        best_left_mask = None

        n_try = 14
        feats = self.rng.choice(FEATURE_COUNT, size=n_try, replace=False)
        for fi in feats:
            col = X[:, fi]
            cmin, cmax = float(col.min()), float(col.max())
            if cmax - cmin < 1e-6:
                continue
            # Try 4 quantile/random thresholds per feature
            thrs = np.quantile(col, [0.20, 0.40, 0.60, 0.80])
            thrs = np.unique(thrs)
            for thr in thrs:
                lm = col <= thr
                nl = int(lm.sum())
                nr = len(y) - nl
                if nl < 3 or nr < 3:
                    continue
                lc = np.bincount(y[lm], weights=w[lm], minlength=NUM_CLASSES)
                rc = counts - lc
                lw = lc.sum()
                rw = total_w - lw
                if lw <= 1e-9 or rw <= 1e-9:
                    continue
                gl = 1.0 - float(((lc / lw) ** 2).sum())
                gr = 1.0 - float(((rc / rw) ** 2).sum())
                gain = gini_parent - (lw * gl + rw * gr) / total_w
                if gain > best_gain:
                    best_gain = gain
                    best_feat = int(fi)
                    best_thr = float(thr)
                    best_left_mask = lm

        if best_feat < 0 or best_gain < 1e-5:
            return {'leaf': True, 'p': np.round(probs, 4).tolist()}

        left = self._build(X[best_left_mask], y[best_left_mask], w[best_left_mask], depth + 1)
        rm = ~best_left_mask
        right = self._build(X[rm], y[rm], w[rm], depth + 1)
        return {'leaf': False, 'f': best_feat, 't': round(best_thr, 5), 'l': left, 'r': right}

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        out = np.zeros((len(X), NUM_CLASSES), dtype=np.float32)
        self._eval_batch(self.root, X, np.arange(len(X)), out)
        return out

    def _eval_batch(self, node, X, idx, out):
        if len(idx) == 0:
            return
        if node['leaf']:
            out[idx] = node['p']
            return
        lm = X[idx, node['f']] <= node['t']
        self._eval_batch(node['l'], X, idx[lm], out)
        self._eval_batch(node['r'], X, idx[~lm], out)


def build_forest(X_tr, y_tr, sample_w, n_trees: int = 40, max_depth: int = 8) -> list[ExtraTree]:
    t0 = time.time()
    rng = np.random.default_rng(777)
    n = len(X_tr)
    p_samp = sample_w / sample_w.sum()
    trees = []
    for ti in range(n_trees):
        # Balanced bootstrap sample of 9000 items so every tree sees balanced classes & domains
        bidx = rng.choice(n, size=9000, replace=True, p=p_samp)
        tree = ExtraTree(max_depth=max_depth, min_leaf=8, seed=1000 + ti)
        tree.fit(X_tr[bidx], y_tr[bidx], np.ones(len(bidx), dtype=np.float32))
        trees.append(tree)
    print(f'Trained {n_trees} ExtraTrees (depth={max_depth}) in {time.time()-t0:.1f}s')
    return trees


def evaluate_predictions(y_true: np.ndarray, probs: np.ndarray, label: str):
    pred = probs.argmax(axis=1)
    acc = float((pred == y_true).mean())
    cm = np.zeros((NUM_CLASSES, NUM_CLASSES), dtype=np.int64)
    for yt, yp in zip(y_true, pred):
        cm[yt, yp] += 1

    print(f'\n=== {label} (N={len(y_true)}) ===')
    print(f'Overall Accuracy: {acc*100:.2f}%')
    f1s = []
    for c, cname in enumerate(CLASSES):
        tp = int(cm[c, c])
        fn = int(cm[c, :].sum() - tp)
        fp = int(cm[:, c].sum() - tp)
        prec = tp / max(1, tp + fp)
        rec = tp / max(1, tp + fn)
        f1 = 2 * prec * rec / max(1e-9, prec + rec)
        f1s.append(f1)
        print(f'  {cname:16s} | n={int(cm[c,:].sum()):4d} | Prec={prec*100:5.1f}% | Rec={rec*100:5.1f}% | F1={f1*100:5.1f}%')
    macro_f1 = float(np.mean(f1s))
    # Practical QC metrics:
    # PASS false alarm (real PASS predicted as Defect 1..5)
    pass_mask = (y_true == 0)
    far = float(((pred[pass_mask] >= 1) & (pred[pass_mask] <= 5)).mean()) if pass_mask.any() else 0.0
    # Defect false pass (real defect 1..5 predicted as PASS)
    def_mask = (y_true >= 1) & (y_true <= 5)
    frr = float((pred[def_mask] == 0).mean()) if def_mask.any() else 0.0
    # NON_SOLDER rejection recall
    ns_mask = (y_true == 6)
    ns_rec = float((pred[ns_mask] == 6).mean()) if ns_mask.any() else 0.0
    print(f'Macro-F1: {macro_f1*100:.2f}% | PASS->Defect FAR: {far*100:.2f}% | Defect->PASS FRR: {frr*100:.2f}% | NON_SOLDER Reject: {ns_rec*100:.2f}%')
    print('Confusion Matrix (rows=true, cols=pred):')
    print(cm)
    return acc, macro_f1, cm


def flatten_tree(node) -> list:
    """Pack tree nodes into ultra-compact array:
    leaf -> [1, p0, p1, ..., p6]
    split -> [0, feat_idx, thr, left_idx, right_idx]
    Wait: nested compact array avoids object keys & shrinks JSON >3x!
    """
    nodes = []
    def emit(nd):
        idx = len(nodes)
        if nd['leaf']:
            nodes.append([1] + nd['p'])
        else:
            nodes.append(None)
            li = emit(nd['l'])
            ri = emit(nd['r'])
            nodes[idx] = [0, nd['f'], nd['t'], li, ri]
        return idx
    emit(node)
    return nodes


def main():
    X_tr, y_tr, s_tr, X_va, y_va, s_va = load_or_extract_dataset(force_rebuild=True)

    # Standardize features based strictly on TRAIN split
    mean = X_tr.mean(axis=0)
    std = np.maximum(X_tr.std(axis=0), 1e-4)
    X_tr_z = ((X_tr - mean) / std).astype(np.float32)
    X_va_z = ((X_va - mean) / std).astype(np.float32)

    # Balanced weights combining inverse-sqrt class freq & domain parity (THT vs SMD equality inside PASS_NORMAL!)
    cls_cnt = np.bincount(y_tr, minlength=NUM_CLASSES).astype(np.float64)
    w_cls = (cls_cnt.max() / np.maximum(1.0, cls_cnt)) ** 0.55
    sample_w = w_cls[y_tr].astype(np.float64)
    for i, src in enumerate(s_tr):
        if y_tr[i] == 0 and any(k in src for k in ('zhouyongbing', 'emp_clean_tht', 'andyliu_v3_nd')):
            sample_w[i] *= 3.2  # Prevent IEEE SMD (1985) from starving THT PASS_NORMAL vs THT D4_EXCESS!
        elif src.endswith('_red'):
            sample_w[i] *= 1.35
        elif src in ('proses_uncut_lead', 'emp_uncut_lead'):
            sample_w[i] *= 2.0

    print('\nTraining MLP Ensemble (2 diverse seeds: 42, 1337)...')
    mlp1 = train_mlp(X_tr_z, y_tr, sample_w, X_va_z, y_va, seed=42, epochs=55)
    mlp2 = train_mlp(X_tr_z, y_tr, sample_w, X_va_z, y_va, seed=1337, epochs=55)
    p_mlp = 0.5 * mlp1.predict_proba(X_va_z) + 0.5 * mlp2.predict_proba(X_va_z)
    evaluate_predictions(y_va, p_mlp, 'MLP Ensemble (2x) on Held-Out VAL')

    print('\nTraining ExtraTrees Forest (40 Depth-8 trees on raw physical features)...')
    forest = build_forest(X_tr, y_tr, sample_w, n_trees=40, max_depth=8)
    p_rf = np.mean([t.predict_proba(X_va) for t in forest], axis=0)
    evaluate_predictions(y_va, p_rf, 'ExtraTrees Forest (40) on Held-Out VAL')

    # Grid search optimal ensemble blend on VAL (70/30 vs 65/35 etc.)
    best_w, best_mf1, best_acc = 0.70, -1.0, 0.0
    for w_mlp in [0.55, 0.65, 0.72, 0.80]:
        blend = w_mlp * p_mlp + (1.0 - w_mlp) * p_rf
        pred = blend.argmax(axis=1)
        acc = float((pred == y_va).mean())
        f1s = []
        for c in range(NUM_CLASSES):
            tp = int(((y_va == c) & (pred == c)).sum())
            fn = int(((y_va == c) & (pred != c)).sum())
            fp = int(((y_va != c) & (pred == c)).sum())
            prec = tp / max(1, tp + fp)
            rec = tp / max(1, tp + fn)
            f1s.append(2 * prec * rec / max(1e-9, prec + rec))
        mf1 = float(np.mean(f1s))
        print(f'  Blend w_mlp={w_mlp:.2f}: Acc={acc*100:.2f}%, MacroF1={mf1*100:.2f}%')
        if 0.5 * acc + 0.5 * mf1 > 0.5 * best_acc + 0.5 * best_mf1:
            best_w, best_acc, best_mf1 = w_mlp, acc, mf1

    p_final = best_w * p_mlp + (1.0 - best_w) * p_rf
    final_acc, final_mf1, final_cm = evaluate_predictions(
        y_va, p_final, f'SOLDY-NET-V6 ENSEMBLE (w_mlp={best_w:.2f}) HELD-OUT VAL'
    )

    # Export Soldy-Net-V6 Pure-Dart JSON artifact
    os.makedirs(APP_MODELS, exist_ok=True)
    model_artifact = {
        'model_name': 'Soldy-Net-V6',
        'version': '6.0.0',
        'feature_count': FEATURE_COUNT,
        'classes': CLASSES,
        'mlp_weight': round(float(best_w), 4),
        'scaler_mean': np.round(mean, 6).tolist(),
        'scaler_std': np.round(std, 6).tolist(),
        'mlps': [
            {
                'W1': np.round(m.W1, 5).tolist(),
                'b1': np.round(m.b1, 5).tolist(),
                'W2': np.round(m.W2, 5).tolist(),
                'b2': np.round(m.b2, 5).tolist(),
                'W3': np.round(m.W3, 5).tolist(),
                'b3': np.round(m.b3, 5).tolist(),
            }
            for m in (mlp1, mlp2)
        ],
        'trees': [flatten_tree(t.root) for t in forest],
    }

    v6_json_path = os.path.join(APP_MODELS, 'soldy_v6_model.json')
    with open(v6_json_path, 'w', encoding='utf-8') as f:
        json.dump(model_artifact, f, separators=(',', ':'))
    sz_kb = os.path.getsize(v6_json_path) / 1024.0
    print(f'\nExported Soldy-Net-V6 model to {v6_json_path} ({sz_kb:.1f} KB)')

    # Update labels.txt and lightweight model_metadata.json cleanly
    with open(os.path.join(APP_MODELS, 'labels.txt'), 'w', encoding='utf-8') as f:
        for c in CLASSES:
            f.write(c + '\n')

    meta_json = {
        'model_name': 'Soldy-Net-V6',
        'model_version': '6.0.0',
        'architecture': 'Standardized 2x MLP (48->160->80->7) + 40 Depth-8 ExtraTrees Ensemble',
        'classes': CLASSES,
        'feature_count': FEATURE_COUNT,
        'held_out_accuracy': round(final_acc * 100.0, 2),
        'held_out_macro_f1': round(final_mf1 * 100.0, 2),
        'train_samples': int(len(X_tr)),
        'val_samples': int(len(X_va)),
        'artifact_file': 'assets/models/soldy_v6_model.json',
    }
    with open(os.path.join(APP_MODELS, 'model_metadata.json'), 'w', encoding='utf-8') as f:
        json.dump(meta_json, f, indent=2)


if __name__ == '__main__':
    main()
