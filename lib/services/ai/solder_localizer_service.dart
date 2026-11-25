import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../core/constants/app_constants.dart';
import '../../core/utils/bounding_box.dart';

/// Detektor Multi-Titik Sambungan Solder Universal (Semua Warna & Bentuk Papan PCB)
/// Dilengkapi segmentasi klaster rona PCB (tolak beton/kertas) dan penapis kaki komponen belum dipotong.
class SolderLocalizerService {
  static final List<double> _cos16 = List<double>.generate(16, (i) => math.cos(i * math.pi / 8.0));
  static final List<double> _sin16 = List<double>.generate(16, (i) => math.sin(i * math.pi / 8.0));

  /// Deteksi otomatis posisi titik sambungan solder di permukaan papan PCB.
  static List<NormalizedBoundingBox> detectSolderJoints(
    img.Image image, {
    int maxJoints = AppConstants.maxJointsPerScan,
  }) {
    final origW = image.width;
    final origH = image.height;
    if (origW <= 8 || origH <= 8) return [];

    // Analisis pada resolusi optimal 1200px sisi panjang agar pad kecil pada foto 12MP tetap tajam
    final longSide = math.max(origW, origH);
    final double scale = longSide > 1200 ? 1200.0 / longSide : 1.0;
    final w = math.max(48, (origW * scale).round());
    final h = math.max(48, (origH * scale).round());

    final small = scale < 0.999
        ? img.copyResize(image, width: w, height: h, interpolation: img.Interpolation.linear)
        : image;

    final n = w * h;
    final invMax = small.maxChannelValue > 0 ? 255.0 / small.maxChannelValue : 1.0;
    final rArr = Float32List(n);
    final gArr = Float32List(n);
    final bArr = Float32List(n);
    final luma = Float32List(n);
    final sat = Float32List(n);
    final whiteFloor = Float32List(n);

    int brightWhitePaper = 0;
    double sumSat = 0.0;

    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        final rr = p.r.toDouble() * invMax;
        final gg = p.g.toDouble() * invMax;
        final bb = p.b.toDouble() * invMax;
        final l = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
        final mx = math.max(rr, math.max(gg, bb));
        final mn = math.min(rr, math.min(gg, bb));
        final s = (mx - mn) / (mx + 1.0);

        rArr[idx] = rr;
        gArr[idx] = gg;
        bArr[idx] = bb;
        luma[idx] = l;
        sat[idx] = s;
        whiteFloor[idx] = mn;
        sumSat += s;
        if (l > 210.0) brightWhitePaper++;
        idx++;
      }
    }

    // Tolak cepat kertas putih / meja pucat netral tanpa papan PCB
    final meanSat = sumSat / n;
    if (brightWhitePaper / n > 0.45 && meanSat < 0.14) {
      return [];
    }

    // 1. Segmentasi klaster warna papan PCB (Red / Green / Blue / Yellow / Obsidian Dark)
    final dRed = Uint8List(n);
    final dGreen = Uint8List(n);
    final dBlue = Uint8List(n);
    final dYellow = Uint8List(n);

    int cRed = 0, cGreen = 0, cBlue = 0, cYellow = 0;
    double satRed = 0, satGreen = 0, satBlue = 0, satYellow = 0;

    for (int i = 0; i < n; i++) {
      final rr = rArr[i], gg = gArr[i], bb = bArr[i];
      final l = luma[i], s = sat[i];
      final chroma = math.max(rr, math.max(gg, bb)) - whiteFloor[i];
      if (chroma >= 35.0 && s >= 0.36 && rr > gg + 35.0 && rr > bb + 20.0 && l >= 22.0 && l <= 185.0) {
        dRed[i] = 1;
        cRed++;
        satRed += s;
      } else if (chroma >= 20.0 && s >= 0.24 && gg > rr + 14.0 && gg > bb + 12.0 && l >= 22.0 && l <= 185.0) {
        dGreen[i] = 1;
        cGreen++;
        satGreen += s;
      } else if (chroma >= 24.0 && s >= 0.26 && bb > rr + 20.0 && bb > gg + 12.0 && l >= 20.0 && l <= 185.0) {
        dBlue[i] = 1;
        cBlue++;
        satBlue += s;
      } else if (chroma >= 40.0 && s >= 0.38 && rr > bb + 40.0 && gg > bb + 30.0 && (rr - gg).abs() < 55.0 && l >= 55.0 && l <= 205.0) {
        dYellow[i] = 1;
        cYellow++;
        satYellow += s;
      }
    }

    Uint8List? bestMask;
    bool isRedBoard = false;
    double bestFamilyScore = 0.0;

    void considerFamily(Uint8List mask, int count, double satSum, bool redFlag) {
      if (count < n * 0.022) return;
      final bw12 = (w + 11) ~/ 12;
      final bh12 = (h + 11) ~/ 12;
      final gsum = Int32List(bw12 * bh12);
      for (int y = 0; y < h; y++) {
        final gy = y ~/ 12;
        for (int x = 0; x < w; x++) {
          if (mask[y * w + x] == 1) {
            gsum[gy * bw12 + (x ~/ 12)]++;
          }
        }
      }
      int denseBlocks = 0;
      for (int k = 0; k < gsum.length; k++) {
        if (gsum[k] >= 55) denseBlocks++;
      }
      if (denseBlocks < 10) return;
      final meanFSat = satSum / count;
      final sc = denseBlocks * math.pow(meanFSat, 1.5).toDouble() * 100.0;
      if (sc > bestFamilyScore) {
        bestFamilyScore = sc;
        bestMask = mask;
        isRedBoard = redFlag;
      }
    }

    considerFamily(dRed, cRed, satRed, true);
    considerFamily(dGreen, cGreen, satGreen, false);
    considerFamily(dBlue, cBlue, satBlue, false);
    considerFamily(dYellow, cYellow, satYellow, false);

    // Fallback papan PCB hitam doff (obsidian smooth mask, tolak beton bertekstur)
    if (bestMask == null) {
      final darkPcb = Uint8List(n);
      int darkCnt = 0;
      int brightMetals = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (luma[i] < 52.0 && sat[i] < 0.25 && (luma[i + 1] - luma[i - 1]).abs() < 14.0) {
            darkPcb[i] = 1;
            darkCnt++;
          }
          if (luma[i] > 165.0 && sat[i] < 0.25) brightMetals++;
        }
      }
      if (darkCnt >= n * 0.08 && brightMetals > 30) {
        bestMask = darkPcb;
      } else {
        return [];
      }
    }

    // 2. Blok grid 8x8 morfologi + pengisian lubang internal + komponen terbesar
    const blk = 8;
    final gw = (w + blk - 1) ~/ blk;
    final gh = (h + blk - 1) ~/ blk;
    final gCount = gw * gh;
    final gridHits = Int32List(gCount);
    final gridTotals = Int32List(gCount);
    for (int y = 0; y < h; y++) {
      final gy = y ~/ blk;
      for (int x = 0; x < w; x++) {
        final gi = gy * gw + (x ~/ blk);
        gridTotals[gi]++;
        if (bestMask![y * w + x] == 1) gridHits[gi]++;
      }
    }

    final gmask = Uint8List(gCount);
    for (int i = 0; i < gCount; i++) {
      if (gridTotals[i] > 0 && gridHits[i] / gridTotals[i] >= 0.16) {
        gmask[i] = 1;
      }
    }

    // Isi lubang internal pad melalui flood-fill dari batas luar tanpa melebarkan tepian bevel FR4
    final extBlank = Uint8List(gCount);
    final q = Queue<int>();
    for (int gy = 0; gy < gh; gy++) {
      for (int gx = 0; gx < gw; gx++) {
        if (gy == 0 || gy == gh - 1 || gx == 0 || gx == gw - 1) {
          final i = gy * gw + gx;
          if (gmask[i] == 0 && extBlank[i] == 0) {
            extBlank[i] = 1;
            q.add(i);
          }
        }
      }
    }
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      final cy = cur ~/ gw, cx = cur % gw;
      for (final d in const [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1],
      ]) {
        final ny = cy + d[0], nx = cx + d[1];
        if (ny >= 0 && ny < gh && nx >= 0 && nx < gw) {
          final ni = ny * gw + nx;
          if (gmask[ni] == 0 && extBlank[ni] == 0) {
            extBlank[ni] = 1;
            q.add(ni);
          }
        }
      }
    }
    final closed = Uint8List(gCount);
    for (int i = 0; i < gCount; i++) {
      closed[i] = extBlank[i] == 0 ? 1 : 0;
    }

    // Komponen terhubung (8-tetangga) pada closed grid
    final compLbl = Int32List(gCount);
    final compSizes = <int>[0];
    int nextLbl = 1;
    for (int i = 0; i < gCount; i++) {
      if (closed[i] == 1 && compLbl[i] == 0) {
        compLbl[i] = nextLbl;
        q.add(i);
        int sz = 0;
        while (q.isNotEmpty) {
          final cur = q.removeFirst();
          sz++;
          final cy = cur ~/ gw, cx = cur % gw;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final ny = cy + dy, nx = cx + dx;
              if (ny >= 0 && ny < gh && nx >= 0 && nx < gw) {
                final ni = ny * gw + nx;
                if (closed[ni] == 1 && compLbl[ni] == 0) {
                  compLbl[ni] = nextLbl;
                  q.add(ni);
                }
              }
            }
          }
        }
        compSizes.add(sz);
        nextLbl++;
      }
    }

    int maxArea = 0;
    for (int k = 1; k < compSizes.length; k++) {
      if (compSizes[k] > maxArea) maxArea = compSizes[k];
    }
    if (maxArea < 6) return [];
    final keepThresh = math.max(6, (maxArea * 0.25).round());

    final pxBoard = Uint8List(n);
    double sumBgL = 0, sumBgL2 = 0, sumBgWf = 0, sumBgWf2 = 0;
    int bgCnt = 0;

    for (int y = 0; y < h; y++) {
      final gy = y ~/ blk;
      for (int x = 0; x < w; x++) {
        final gi = gy * gw + (x ~/ blk);
        final lbl = compLbl[gi];
        if (lbl > 0 && compSizes[lbl] >= keepThresh) {
          final i = y * w + x;
          pxBoard[i] = 1;
          if (bestMask![i] == 1) {
            final l = luma[i];
            final wf = whiteFloor[i];
            sumBgL += l;
            sumBgL2 += l * l;
            sumBgWf += wf;
            sumBgWf2 += wf * wf;
            bgCnt++;
          }
        }
      }
    }
    if (bgCnt < 40) return [];

    final boardMean = sumBgL / bgCnt;
    final boardStd = math.sqrt(math.max(0.0, (sumBgL2 / bgCnt) - boardMean * boardMean));
    final wfMean = sumBgWf / bgCnt;
    final wfStd = math.sqrt(math.max(0.0, (sumBgWf2 / bgCnt) - wfMean * wfMean));

    final solderLumaThr = math.min(195.0, math.max(92.0, boardMean + math.max(26.0, boardStd * 1.05)));
    final solderWfThr = math.min(160.0, math.max(54.0, wfMean + math.max(28.0, wfStd * 1.5)));
    final haloWfThr = math.min(140.0, math.max(40.0, wfMean + math.max(17.0, wfStd * 0.95)));
    final haloLumaThr = math.min(175.0, math.max(78.0, boardMean + math.max(16.0, boardStd * 0.65)));
    final maxJointSat = isRedBoard ? 0.44 : 0.34;
    final softHaloLuma = haloLumaThr * 0.85;
    final softHaloWf = haloWfThr * 0.82;

    // 3. Ekstraksi Puncak Logam Lokal + Filter 16-Ray Penolak Kaki Komponen Belum Potong
    final metalScore = Float32List(n);
    for (int i = 0; i < n; i++) {
      metalScore[i] = math.min(luma[i], whiteFloor[i] * 1.35 + 15.0);
    }

    final minR = math.max(3, (math.min(w, h) * 0.004).round());
    final maxTrace = math.min(48, math.max(24, (math.min(w, h) * 0.055).round()));
    final peaks = <_JointCandidate>[];
    final radii = Int32List(16);
    final wireRadii = Int32List(16);
    final diams = List<int>.filled(8, 0);
    final wDiams = List<int>.filled(8, 0);

    for (int y = 8; y < h - 8; y++) {
      for (int x = 8; x < w - 8; x++) {
        final i = y * w + x;
        if (pxBoard[i] == 0) continue;
        // Wajib berada >= 6px di dalam papan PCB dari 4 arah (cegah garis bevel luar FR4)
        if (pxBoard[(y - 6) * w + x] == 0 ||
            pxBoard[(y + 6) * w + x] == 0 ||
            pxBoard[y * w + (x - 6)] == 0 ||
            pxBoard[y * w + (x + 6)] == 0) {
          continue;
        }
        final v = luma[i];
        if (v < solderLumaThr || whiteFloor[i] < solderWfThr || sat[i] > maxJointSat) continue;

        final ms = metalScore[i];
        bool isLocalMax = true;
        for (int dy = -4; dy <= 4 && isLocalMax; dy++) {
          final rowOff = (y + dy) * w;
          for (int dx = -4; dx <= 4; dx++) {
            if (metalScore[rowOff + x + dx] > ms + 0.1) {
              isLocalMax = false;
              break;
            }
          }
        }
        if (!isLocalMax) continue;

        // Pastikan tetangga mengandung papan PCB asli (hindari tepian kertas tempel)
        final yA = math.max(0, y - 22), yB = math.min(h, y + 23);
        final xA = math.max(0, x - 22), xB = math.min(w, x + 23);
        int maskHits = 0;
        for (int ry = yA; ry < yB; ry += 2) {
          for (int rx = xA; rx < xB; rx += 2) {
            if (bestMask![ry * w + rx] == 1) maskHits++;
          }
        }
        final sampleTot = ((yB - yA + 1) ~/ 2) * ((xB - xA + 1) ~/ 2);
        if (sampleTot == 0 || maskHits / sampleTot < 0.18) continue;

        // Lacak 16 sinar radial logam (dengan toleransi jeda kilap 2px untuk deteksi kaki kawat utuh)
        for (int ai = 0; ai < 16; ai++) {
          final ca = _cos16[ai], sa = _sin16[ai];
          int dist = 0, wdist = 0, gap = 0;
          bool solidBroken = false;
          for (int step = 1; step <= maxTrace; step++) {
            final rx = (x + ca * step).round();
            final ry = (y + sa * step).round();
            if (rx < 1 || rx >= w - 1 || ry < 1 || ry >= h - 1) break;
            final ri = ry * w + rx;
            final isStrict = luma[ri] >= haloLumaThr &&
                whiteFloor[ri] >= haloWfThr &&
                sat[ri] <= (maxJointSat + 0.06) &&
                pxBoard[ri] == 1;
            final isWire = luma[ri] >= softHaloLuma &&
                whiteFloor[ri] >= softHaloWf &&
                sat[ri] <= (maxJointSat + 0.08);
            if (isStrict && !solidBroken) {
              dist = step;
            } else {
              solidBroken = true;
            }
            if (isWire) {
              wdist = step;
              gap = 0;
            } else {
              gap++;
              if (gap > 2) break;
            }
          }
          radii[ai] = dist;
          wireRadii[ai] = wdist;
        }

        for (int k = 0; k < 8; k++) {
          diams[k] = radii[k] + radii[k + 8];
          wDiams[k] = wireRadii[k] + wireRadii[k + 8];
        }
        final sortedD = List<int>.from(diams)..sort();
        final sortedW = List<int>.from(wDiams)..sort();
        final p25Diam = sortedD[2];
        final medDiam = sortedD[4];

        int maxWdiam = 0;
        int maxWk = 0;
        for (int k = 0; k < 8; k++) {
          if (wDiams[k] > maxWdiam) {
            maxWdiam = wDiams[k];
            maxWk = k;
          }
        }
        final oppWmin = math.min(wireRadii[maxWk], wireRadii[maxWk + 8]);
        final perpWdiam = wDiams[(maxWk + 4) % 8];
        final wAspect = maxWdiam / math.max(1.0, perpWdiam.toDouble());
        final p12Wdiam = sortedW[1];
        final p25Wdiam = sortedW[2];
        final medWdiam = sortedW[4];

        // Terima kerucut timah cekung kilap netral (dome perak kompak walau setengah sisinya bayangan)
        final bool isSilverDome = whiteFloor[i] >= 120.0 &&
            sat[i] <= 0.24 &&
            medWdiam >= 6 &&
            p25Wdiam >= 5 &&
            maxWdiam <= 26;
        if (medDiam < math.max(5, (minR * 1.4).round()) && !isSilverDome) continue;

        // Tolak kawat kaki komponen tipis 1D belum terpotong (ujung kawat, badan kawat, maupun bersilangan +/X)
        if (perpWdiam <= 7 && maxWdiam >= 18 && wAspect >= 3.0) continue;
        if (perpWdiam <= 7 && maxWdiam >= 16 && oppWmin >= 5 && wAspect >= 2.3) continue;
        if (p25Wdiam <= 7 && maxWdiam >= 15 && oppWmin >= 4 && (maxWdiam / math.max(1.0, p25Wdiam.toDouble())) >= 2.4) continue;
        if (sortedW[0] <= 4 && maxWdiam >= 14 && oppWmin >= 4) continue;
        if (p12Wdiam <= 7 && p25Wdiam <= 9 && maxWdiam >= 24 && (maxWdiam / math.max(1.0, p25Wdiam.toDouble())) >= 3.0) continue;
        if (p12Wdiam <= 12 && maxWdiam >= 24 && perpWdiam >= p12Wdiam * 2.4 && maxWdiam >= p12Wdiam * 2.8) continue;
        if (medDiam > math.min(w, h) * 0.058) continue;

        final aspect = sortedD.last / math.max(1.0, p25Diam.toDouble());
        final double boxD = math.min(
          56.0,
          math.max(
            28.0,
            math.min(
              math.max(medDiam, medWdiam) * 2.1,
              math.max(p25Diam, p25Wdiam) * 2.6,
            ),
          ),
        );
        final score = whiteFloor[i] + v * 0.4 + p25Wdiam * 6.0 - math.max(0.0, aspect - 2.0) * 10.0;
        peaks.add(_JointCandidate(cx: x.toDouble(), cy: y.toDouble(), boxSize: boxD, score: score));
      }
    }

    peaks.sort((a, b) => b.score.compareTo(a.score));

    final selected = <_JointCandidate>[];
    for (final c in peaks) {
      if (selected.length >= maxJoints) break;
      final half = c.boxSize * 0.5;
      bool overlaps = false;
      for (final s in selected) {
        final sHalf = s.boxSize * 0.5;
        if ((c.cx - s.cx).abs() < (half + sHalf) * 0.54 && (c.cy - s.cy).abs() < (half + sHalf) * 0.54) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) selected.add(c);
    }

    return selected.map((c) {
      final bw = (c.boxSize / w).clamp(0.015, 0.32);
      final bh = (c.boxSize / h).clamp(0.015, 0.32);
      return NormalizedBoundingBox(
        x: ((c.cx / w) - bw * 0.5).clamp(0.0, 1.0 - bw),
        y: ((c.cy / h) - bh * 0.5).clamp(0.0, 1.0 - bh),
        width: bw,
        height: bh,
      );
    }).toList();
  }

  /// Deteksi ringan khusus kamera pratinjau langsung (`bytes` bidang luminansi Y).
  static List<NormalizedBoundingBox> detectFromLuminanceBuffer({
    required List<int> yPlaneBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    int maxJoints = AppConstants.maxJointsLivePreview,
  }) {
    return analyzeLiveLuminanceFrame(
      yPlaneBytes: yPlaneBytes,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      maxJoints: maxJoints,
    ).boxes;
  }

  /// Analisis frame pratinjau kamera real-time (< 3 ms) termasuk penolakan kawat kaki komponen utuh & kertas.
  static LiveFrameAnalysis analyzeLiveLuminanceFrame({
    required List<int> yPlaneBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    int maxJoints = AppConstants.maxJointsLivePreview,
  }) {
    if (width <= 0 || height <= 0 || yPlaneBytes.isEmpty) {
      return const LiveFrameAnalysis(
        boxes: [],
        lightStatus: 'OPTIMAL',
        focusStatus: 'SHARP',
        averageLuma: 128.0,
      );
    }

    const int sw = 160;
    const int sh = 120;
    final lumaGrid = Float32List(sw * sh);
    final scaleX = width / sw;
    final scaleY = height / sh;

    double sumLuma = 0;
    int darkBoardCount = 0;
    int veryBrightPaperCount = 0;

    for (int gy = 0; gy < sh; gy++) {
      final srcY = (gy * scaleY).toInt().clamp(0, height - 1);
      final rowOffset = srcY * bytesPerRow;
      for (int gx = 0; gx < sw; gx++) {
        final srcX = (gx * scaleX).toInt().clamp(0, width - 1);
        final idx = rowOffset + srcX;
        final val = idx < yPlaneBytes.length ? (yPlaneBytes[idx] & 0xFF).toDouble() : 128.0;
        lumaGrid[gy * sw + gx] = val;
        sumLuma += val;
        if (val < 118.0) darkBoardCount++;
        if (val > 215.0) veryBrightPaperCount++;
      }
    }

    const total = sw * sh;
    final avgLuma = sumLuma / total;
    String lightStatus = 'OPTIMAL';
    if (avgLuma < AppConstants.defaultBrightnessMin) {
      lightStatus = 'LOW';
    } else if (avgLuma > AppConstants.defaultBrightnessMax) {
      lightStatus = 'HIGH';
    }

    // Ketajaman fokus Laplacian pada tengah 50% grid
    double lapSum = 0;
    int lapCount = 0;
    for (int gy = 30; gy < 90; gy++) {
      for (int gx = 40; gx < 120; gx++) {
        final c = lumaGrid[gy * sw + gx];
        final l = lumaGrid[gy * sw + (gx - 1)];
        final r = lumaGrid[gy * sw + (gx + 1)];
        final t = lumaGrid[(gy - 1) * sw + gx];
        final b = lumaGrid[(gy + 1) * sw + gx];
        final lap = (4 * c - l - r - t - b).abs();
        lapSum += lap;
        lapCount++;
      }
    }
    final avgSharpness = lapCount > 0 ? lapSum / lapCount : 25.0;
    final focusStatus = avgSharpness >= 11.5 ? 'SHARP' : 'BLURRY';

    if (veryBrightPaperCount / total > 0.50 || darkBoardCount / total < 0.08) {
      return LiveFrameAnalysis(
        boxes: const [],
        lightStatus: lightStatus,
        focusStatus: focusStatus,
        averageLuma: avgLuma,
      );
    }

    final solderThreshold = math.min(220.0, math.max(125.0, avgLuma + 28.0));
    final haloThreshold = math.min(198.0, math.max(100.0, avgLuma + 14.0));
    final candidates = <_JointCandidate>[];
    final radii = Int32List(8);
    const dx8 = [1, 1, 0, -1, -1, -1, 0, 1];
    const dy8 = [0, 1, 1, 1, 0, -1, -1, -1];

    for (int gy = 6; gy < sh - 6; gy += 2) {
      for (int gx = 6; gx < sw - 6; gx += 2) {
        final v = lumaGrid[gy * sw + gx];
        if (v < solderThreshold) continue;

        bool isLocalMax = true;
        for (int dy = -2; dy <= 2 && isLocalMax; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            if (lumaGrid[(gy + dy) * sw + (gx + dx)] > v + 0.5) {
              isLocalMax = false;
              break;
            }
          }
        }
        if (!isLocalMax) continue;

        int maxR = 0;
        int maxAxis = 0;
        for (int ai = 0; ai < 8; ai++) {
          int d = 0;
          int gap = 0;
          for (int s = 1; s <= 12; s++) {
            final nx = gx + dx8[ai] * s;
            final ny = gy + dy8[ai] * s;
            if (nx < 1 || nx >= sw - 1 || ny < 1 || ny >= sh - 1) break;
            if (lumaGrid[ny * sw + nx] >= haloThreshold) {
              d = s;
              gap = 0;
            } else {
              gap++;
              if (gap > 1) break;
            }
          }
          radii[ai] = d;
          if (d > maxR) {
            maxR = d;
            maxAxis = ai;
          }
        }

        // Tolak kaki kawat utuh di pratinjau live
        final d0 = radii[0] + radii[4];
        final d1 = radii[1] + radii[5];
        final d2 = radii[2] + radii[6];
        final d3 = radii[3] + radii[7];
        final axes = [d0, d1, d2, d3]..sort();
        final oppMin = math.min(radii[maxAxis], radii[(maxAxis + 4) % 8]);
        if (axes[0] <= 3 && axes.last >= 8 && oppMin >= 3 && (axes.last / math.max(1, axes[0])) >= 2.3) {
          continue;
        }
        if (axes[1] < 2 || axes[2] > 20) continue;

        final boxSize = math.max(7.0, math.min(18.0, axes[1] * 2.2));
        candidates.add(_JointCandidate(
          cx: gx.toDouble(),
          cy: gy.toDouble(),
          boxSize: boxSize,
          score: v + axes[1] * 6.0,
        ));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final selected = <_JointCandidate>[];
    for (final c in candidates) {
      if (selected.length >= maxJoints) break;
      final half = c.boxSize * 0.5;
      bool overlaps = false;
      for (final s in selected) {
        final shHalf = s.boxSize * 0.5;
        if ((c.cx - s.cx).abs() < (half + shHalf) * 0.6 && (c.cy - s.cy).abs() < (half + shHalf) * 0.6) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) selected.add(c);
    }

    final boxes = selected.map((c) {
      final bw = (c.boxSize / sw).clamp(0.03, 0.25);
      final bh = (c.boxSize / sh).clamp(0.03, 0.25);
      return NormalizedBoundingBox(
        x: ((c.cx / sw) - bw * 0.5).clamp(0.0, 1.0 - bw),
        y: ((c.cy / sh) - bh * 0.5).clamp(0.0, 1.0 - bh),
        width: bw,
        height: bh,
      );
    }).toList();

    return LiveFrameAnalysis(
      boxes: boxes,
      lightStatus: lightStatus,
      focusStatus: focusStatus,
      averageLuma: avgLuma,
    );
  }
}

class _JointCandidate {
  final double cx;
  final double cy;
  final double boxSize;
  final double score;

  _JointCandidate({
    required this.cx,
    required this.cy,
    required this.boxSize,
    required this.score,
  });
}

/// Hasil lengkap analisis frame kamera secara real-time (deteksi + status cahaya & fokus)
class LiveFrameAnalysis {
  final List<NormalizedBoundingBox> boxes;
  final String lightStatus;
  final String focusStatus;
  final double averageLuma;

  const LiveFrameAnalysis({
    required this.boxes,
    required this.lightStatus,
    required this.focusStatus,
    required this.averageLuma,
  });
}
