# Soldy AI Training Pipeline (`Soldy-Net-V6`)

Offline Python pipeline used to curate multi-source THT/SMD solder joint patches, train the hybrid 2x MLP + 40 Depth-8 ExtraTrees model, and export pure-Dart JSON weights to `assets/models/soldy_v6_model.json`.

## Scripts

- `soldy_features.py`: 48-dimensional domain-invariant concentric photometry, gradient/Laplacian, second-moment morphometry, and 8-ray uncut wire detector (must match `SoldyV6FeatureExtractor` in `lib/services/ai/solder_model_engine.dart`).
- `build_soldy_dataset.py`: Curates leak-free 7-class train/val splits across open-source SMD/THT datasets and optional work-in-progress negative directories (`SOLDERLAB_WIP_PHOTOS`).
- `train_soldy_v6.py`: Trains the standardized ensemble with color-mask invariance augmentation and exports JSON weights.
- `test_v6_real_photos.py`: Runs local PCB segmentation + CV 16-ray uncut-lead filtering + `Soldy-Net-V6` classification over sample fixtures or custom photo directories.

## Quick Run

```bash
pip install numpy pandas pillow scipy
python test_v6_real_photos.py
```
