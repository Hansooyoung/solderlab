import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import '../../core/constants/app_constants.dart';

/// 11 Fitur Ekstraksi Morfologi & Fotometri Klasik (Tetap dipertahankan untuk kompatibilitas API)
class SolderFeatures {
  final double meanLuma;
  final double stdLuma;
  final double p90Luma;
  final double p10Luma;
  final double brightRatio;
  final double darkRatio;
  final double meanGrad;
  final double stdGrad;
  final double meanSat;
  final double aspectAsymmetry;
  final double centerContrast;

  const SolderFeatures({
    required this.meanLuma,
    required this.stdLuma,
    required this.p90Luma,
    required this.p10Luma,
    required this.brightRatio,
    required this.darkRatio,
    required this.meanGrad,
    required this.stdGrad,
    required this.meanSat,
    required this.aspectAsymmetry,
    required this.centerContrast,
  });

  List<double> toVector() => [
        meanLuma,
        stdLuma,
        p90Luma,
        p10Luma,
        brightRatio,
        darkRatio,
        meanGrad,
        stdGrad,
        meanSat,
        aspectAsymmetry,
        centerContrast,
      ];

  /// Ekstraksi cepat 11 fitur morfologi & fotometri klasik untuk kompatibilitas mundur.
  static SolderFeatures extract(img.Image patch) {
    final small = img.copyResize(patch, width: 64, height: 64, interpolation: img.Interpolation.linear);
    const n = 64 * 64;
    final luma = Float64List(n);
    final satList = Float64List(n);
    final invMax = small.maxChannelValue > 0 ? 255.0 / small.maxChannelValue : 1.0;

    int brightCount = 0;
    int darkCount = 0;
    double sumL = 0.0;
    double sumSat = 0.0;
    double cLumaSum = 0.0;
    int cCount = 0;
    double bLumaSum = 0.0;
    int bCount = 0;

    int idx = 0;
    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toDouble() * invMax;
        final g = p.g.toDouble() * invMax;
        final b = p.b.toDouble() * invMax;
        final yVal = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final sVal = (maxC - minC) / (maxC + 1.0);

        luma[idx] = yVal;
        satList[idx] = sVal;
        sumL += yVal;
        sumSat += sVal;

        if (yVal > 180.0) brightCount++;
        if (yVal < 75.0) darkCount++;

        if (x >= 16 && x < 48 && y >= 16 && y < 48) {
          cLumaSum += yVal;
          cCount++;
        } else {
          bLumaSum += yVal;
          bCount++;
        }
        idx++;
      }
    }

    final meanL = sumL / n;
    double sqSum = 0.0;
    for (int i = 0; i < n; i++) {
      final d = luma[i] - meanL;
      sqSum += d * d;
    }
    final stdL = math.sqrt(sqSum / n);

    final sortedL = Float64List.fromList(luma)..sort();
    final p10 = sortedL[(n * 0.10).toInt()];
    final p90 = sortedL[(n * 0.90).toInt()];

    const gradCount = 62 * 62;
    final grad = Float64List(gradCount);
    double sumG = 0.0;
    int gIdx = 0;
    for (int y = 1; y < 63; y++) {
      for (int x = 1; x < 63; x++) {
        final gx = (luma[y * 64 + (x + 1)] - luma[y * 64 + (x - 1)]).abs() * 0.5;
        final gy = (luma[(y + 1) * 64 + x] - luma[(y - 1) * 64 + x]).abs() * 0.5;
        final mag = gx + gy;
        grad[gIdx++] = mag;
        sumG += mag;
      }
    }
    final meanG = sumG / gradCount;
    double sqG = 0.0;
    for (int i = 0; i < gradCount; i++) {
      final d = grad[i] - meanG;
      sqG += d * d;
    }
    final stdG = math.sqrt(sqG / gradCount);

    final cMean = cLumaSum / cCount;
    final bMean = bLumaSum / bCount;
    final centerC = cMean - bMean;
    final minDim = math.min(patch.width, patch.height).toDouble();
    final maxDim = math.max(1, math.max(patch.width, patch.height)).toDouble();

    return SolderFeatures(
      meanLuma: meanL,
      stdLuma: stdL,
      p90Luma: p90,
      p10Luma: p10,
      brightRatio: brightCount / n,
      darkRatio: darkCount / n,
      meanGrad: meanG,
      stdGrad: stdG,
      meanSat: sumSat / n,
      aspectAsymmetry: minDim / maxDim,
      centerContrast: centerC,
    );
  }
}

/// Ekstraktor Fitur 48-Dimensi Invarian Domain Soldy-Net-V6 (100% sinkron bit-ke-bit dengan Python soldy_features.py).
class SoldyV6FeatureExtractor {
  static const int featureCount = 48;
  static const int gridN = 32;
  static const int totalPx = gridN * gridN;

  static final _Masks _m = _Masks();

  static Float32List extract(img.Image patch) {
    final w = patch.width;
    final h = patch.height;
    final f = Float32List(featureCount);
    if (w <= 0 || h <= 0) return f;

    final invMax = patch.maxChannelValue > 0 ? 1.0 / patch.maxChannelValue : 1.0 / 255.0;
    final rArr = Float32List(totalPx);
    final gArr = Float32List(totalPx);
    final bArr = Float32List(totalPx);
    final yArr = Float32List(totalPx);
    final satArr = Float32List(totalPx);

    // Bilinear sampling exact match: gx = x * (w - 1) / 31.0, gy = y * (h - 1) / 31.0
    final sxScale = w > 1 ? (w - 1) / 31.0 : 0.0;
    final syScale = h > 1 ? (h - 1) / 31.0 : 0.0;

    int pIdx = 0;
    for (int gy = 0; gy < gridN; gy++) {
      final fy = gy * syScale;
      final y0 = fy.floor().clamp(0, h - 1);
      final y1 = (y0 + 1).clamp(0, h - 1);
      final wy = fy - y0;
      final iwy = 1.0 - wy;

      for (int gx = 0; gx < gridN; gx++) {
        final fx = gx * sxScale;
        final x0 = fx.floor().clamp(0, w - 1);
        final x1 = (x0 + 1).clamp(0, w - 1);
        final wx = fx - x0;
        final iwx = 1.0 - wx;

        final p00 = patch.getPixel(x0, y0);
        final p10 = patch.getPixel(x1, y0);
        final p01 = patch.getPixel(x0, y1);
        final p11 = patch.getPixel(x1, y1);

        final rr = ((p00.r * iwx + p10.r * wx) * iwy + (p01.r * iwx + p11.r * wx) * wy) * invMax;
        final gg = ((p00.g * iwx + p10.g * wx) * iwy + (p01.g * iwx + p11.g * wx) * wy) * invMax;
        final bb = ((p00.b * iwx + p10.b * wx) * iwy + (p01.b * iwx + p11.b * wx) * wy) * invMax;

        rArr[pIdx] = rr;
        gArr[pIdx] = gg;
        bArr[pIdx] = bb;
        final l = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
        yArr[pIdx] = l;
        final mx = math.max(rr, math.max(gg, bb));
        final mn = math.min(rr, math.min(gg, bb));
        satArr[pIdx] = (mx - mn) / (mx + 1e-4);
        pIdx++;
      }
    }

    double sumY = 0.0;
    double coreYSum = 0.0;
    double midYSum = 0.0;
    double outerYSum = 0.0;
    int darkCorePit = 0;
    int specCore45 = 0;
    int metalIn65 = 0;
    int metalOuter = 0;
    final metal = Uint8List(totalPx);

    for (int i = 0; i < totalPx; i++) {
      final yv = yArr[i];
      final sv = satArr[i];
      sumY += yv;
      final isM = (yv > 0.48 && sv < 0.26) ? 1 : 0;
      metal[i] = isM;

      if (_m.isCore[i]) {
        coreYSum += yv;
        if (yv < 0.22) darkCorePit++;
      } else if (_m.isMid[i]) {
        midYSum += yv;
      } else {
        outerYSum += yv;
        if (isM == 1) metalOuter++;
      }
      if (_m.isCore45[i] && yv > 0.78 && sv < 0.22) specCore45++;
      if (_m.isIn65[i] && isM == 1) metalIn65++;
    }

    final lumaMean = sumY / totalPx;
    double sqSum = 0.0;
    for (int i = 0; i < totalPx; i++) {
      final d = yArr[i] - lumaMean;
      sqSum += d * d;
    }
    final lumaStd = math.sqrt(sqSum / totalPx);
    final coreLuma = coreYSum / _m.coreCount;
    final midLuma = midYSum / _m.midCount;
    final outerLuma = outerYSum / _m.outerCount;

    final grad = Float32List(totalPx);
    final lap = Float32List(totalPx);
    double gradSum = 0.0;
    double grad55Sum = 0.0;
    int grad55Count = 0;
    double metalLapSum = 0.0;
    int metalLapCount = 0;
    final in60Lap = <double>[];

    for (int y = 0; y < gridN; y++) {
      for (int x = 0; x < gridN; x++) {
        final i = y * gridN + x;
        if (y >= 1 && y < gridN - 1 && x >= 1 && x < gridN - 1) {
          final gx = (yArr[i + 1] - yArr[i - 1]).abs() * 0.5;
          final gy = (yArr[i + gridN] - yArr[i - gridN]).abs() * 0.5;
          final gVal = gx + gy;
          final lVal = (4.0 * yArr[i] - yArr[i - gridN] - yArr[i + gridN] - yArr[i - 1] - yArr[i + 1]).abs();
          grad[i] = gVal;
          lap[i] = lVal;
          gradSum += gVal;
          if (_m.radius[i] <= 0.55) {
            grad55Sum += gVal;
            grad55Count++;
          }
          if (yArr[i] > 0.35 && satArr[i] < 0.28) {
            metalLapSum += lVal;
            metalLapCount++;
          }
          if (_m.isIn60[i]) in60Lap.add(lVal);
        } else {
          if (_m.radius[i] <= 0.55) grad55Count++;
          if (_m.isIn60[i]) in60Lap.add(0.0);
        }
      }
    }

    f[0] = lumaMean;
    f[1] = lumaStd;
    f[2] = coreLuma;
    f[3] = midLuma;
    f[4] = outerLuma;
    f[5] = coreLuma - midLuma;
    f[6] = midLuma - outerLuma;
    f[7] = darkCorePit / _m.coreCount;
    f[8] = specCore45 / _m.core45Count;
    f[9] = metalIn65 / _m.in65Count;
    f[10] = metalOuter / _m.outerCount;

    double topM = 0, botM = 0, leftM = 0, rightM = 0;
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < gridN; x++) {
        if (metal[y * gridN + x] == 1) topM++;
        if (metal[(gridN - 1 - y) * gridN + x] == 1) botM++;
      }
    }
    for (int x = 0; x < 3; x++) {
      for (int y = 0; y < gridN; y++) {
        if (metal[y * gridN + x] == 1) leftM++;
        if (metal[y * gridN + (gridN - 1 - x)] == 1) rightM++;
      }
    }
    topM /= (3 * gridN);
    botM /= (3 * gridN);
    leftM /= (3 * gridN);
    rightM /= (3 * gridN);
    f[11] = math.max(math.max(topM, botM), math.max(leftM, rightM));

    final ySorted = Float32List.fromList(yArr)..sort();
    f[12] = ySorted[921] - ySorted[102];

    double q1 = 0, q2 = 0, q3 = 0, q4 = 0;
    double qm1 = 0, qm2 = 0, qm3 = 0, qm4 = 0;
    for (int y = 0; y < gridN; y++) {
      for (int x = 0; x < gridN; x++) {
        final i = y * gridN + x;
        final yv = yArr[i];
        final mv = metal[i].toDouble();
        if (y < 16) {
          if (x < 16) {
            q1 += yv;
            qm1 += mv;
          } else {
            q2 += yv;
            qm2 += mv;
          }
        } else {
          if (x < 16) {
            q3 += yv;
            qm3 += mv;
          } else {
            q4 += yv;
            qm4 += mv;
          }
        }
      }
    }
    q1 /= 256.0;
    q2 /= 256.0;
    q3 /= 256.0;
    q4 /= 256.0;
    final qMean = (q1 + q2 + q3 + q4) * 0.25;
    final qStd = math.sqrt(((q1 - qMean) * (q1 - qMean) + (q2 - qMean) * (q2 - qMean) + (q3 - qMean) * (q3 - qMean) + (q4 - qMean) * (q4 - qMean)) * 0.25);
    f[13] = math.max(0.0, 1.0 - qStd * 3.0);

    f[14] = gradSum / totalPx;
    f[15] = grad55Count > 0 ? grad55Sum / grad55Count : 0.0;
    f[16] = metalLapCount > 0 ? metalLapSum / metalLapCount : 0.0;
    in60Lap.sort();
    f[17] = in60Lap.isNotEmpty ? in60Lap[(in60Lap.length * 0.90).floor().clamp(0, in60Lap.length - 1)] : 0.0;

    int darkPocket = 0;
    double donutSum = 0.0;
    double center18Sum = 0.0;
    int core55Count = 0;
    int mid45Count = 0;
    final hist = Int32List(8);

    double y75Sum = 0.0;
    final y75 = <double>[];

    for (int i = 0; i < totalPx; i++) {
      final yv = yArr[i];
      if (_m.isCore28[i] && yv < midLuma - 0.16) darkPocket++;
      if (_m.isRingDonut[i]) donutSum += yv;
      if (_m.isCenter18[i]) center18Sum += yv;
      if (_m.isCore[i] && yv > 0.55) core55Count++;
      if (_m.isMid[i] && yv > 0.45) mid45Count++;
      final b = (yv * 7.999).floor().clamp(0, 7);
      hist[b]++;
      if (_m.isIn75[i]) {
        y75.add(yv);
        y75Sum += yv;
      }
    }

    f[18] = darkPocket / _m.core28Count;
    f[19] = (donutSum / _m.ringDonutCount) - (center18Sum / _m.center18Count);

    double ent = 0.0;
    final log8 = math.log(8.0);
    for (int b = 0; b < 8; b++) {
      if (hist[b] > 0) {
        final pr = hist[b] / 1024.0;
        ent -= pr * math.log(pr);
      }
    }
    f[20] = ent / log8;
    f[21] = (core55Count / _m.coreCount + 0.01) / (mid45Count / _m.midCount + 0.05);

    int exits = 0;
    if (topM > 0.12) exits++;
    if (botM > 0.12) exits++;
    if (leftM > 0.12) exits++;
    if (rightM > 0.12) exits++;
    f[22] = exits / 4.0;

    int cmH = 0, cmV = 0;
    for (int y = 0; y < gridN; y++) {
      for (int x = 0; x < gridN; x++) {
        if (y >= 13 && y < 19 && metal[y * gridN + x] == 1) cmH++;
        if (x >= 13 && x < 19 && metal[y * gridN + x] == 1) cmV++;
      }
    }
    f[23] = math.max(math.min(topM, botM) * (cmV / (6 * gridN)), math.min(leftM, rightM) * (cmH / (6 * gridN)));

    final rowM = Float32List(gridN);
    final colM = Float32List(gridN);
    for (int y = 0; y < gridN; y++) {
      int rs = 0;
      for (int x = 0; x < gridN; x++) {
        rs += metal[y * gridN + x];
        colM[x] += metal[y * gridN + x];
      }
      rowM[y] = rs / gridN;
    }
    for (int x = 0; x < gridN; x++) {
      colM[x] /= gridN;
    }

    double hA = 0, hB = 0, hW = 1.0, vA = 0, vB = 0, vW = 1.0;
    for (int k = 3; k < 12; k++) {
      if (rowM[k] > hA) hA = rowM[k];
      if (colM[k] > vA) vA = colM[k];
    }
    for (int k = 20; k < 29; k++) {
      if (rowM[k] > hB) hB = rowM[k];
      if (colM[k] > vB) vB = colM[k];
    }
    for (int k = 12; k < 20; k++) {
      if (rowM[k] < hW) hW = rowM[k];
      if (colM[k] < vW) vW = colM[k];
    }
    final hEnds = math.min(hA, hB);
    final vEnds = math.min(vA, vB);
    f[24] = math.max(hEnds > 0.15 ? (hEnds - hW) : 0.0, vEnds > 0.15 ? (vEnds - vW) : 0.0);

    final y75Mean = y75Sum / y75.length;
    double highSum = 0, lowSum = 0, y75Var = 0;
    int highCnt = 0, lowCnt = 0;
    for (final v in y75) {
      final d = v - y75Mean;
      y75Var += d * d;
      if (v >= y75Mean) {
        highSum += v;
        highCnt++;
      } else {
        lowSum += v;
        lowCnt++;
      }
    }
    y75Var /= y75.length;
    if (highCnt > 0 && lowCnt > 0) {
      final w1 = highCnt / y75.length;
      final w0 = lowCnt / y75.length;
      final diffM = (highSum / highCnt) - (lowSum / lowCnt);
      f[25] = (w0 * w1 * diffM * diffM) / (y75Var + 1e-4);
    }

    // Group C: Morphometry & Second Moments
    int mCount = 0;
    double sumMx = 0, sumMy = 0;
    int minMx = gridN, maxMx = 0, minMy = gridN, maxMy = 0;
    for (int y = 0; y < gridN; y++) {
      for (int x = 0; x < gridN; x++) {
        if (metal[y * gridN + x] == 1) {
          mCount++;
          sumMx += x;
          sumMy += y;
          if (x < minMx) minMx = x;
          if (x > maxMx) maxMx = x;
          if (y < minMy) minMy = y;
          if (y > maxMy) maxMy = y;
        }
      }
    }
    if (mCount >= 4) {
      final cx = sumMx / mCount;
      final cy = sumMy / mCount;
      double cxx = 0, cyy = 0, cxy = 0;
      for (int y = 0; y < gridN; y++) {
        for (int x = 0; x < gridN; x++) {
          if (metal[y * gridN + x] == 1) {
            final dx = x - cx;
            final dy = y - cy;
            cxx += dx * dx;
            cyy += dy * dy;
            cxy += dx * dy;
          }
        }
      }
      cxx /= mCount;
      cyy /= mCount;
      cxy /= mCount;
      final tr = cxx + cyy;
      final diff = math.sqrt((cxx - cyy) * (cxx - cyy) + 4.0 * cxy * cxy);
      final lam1 = math.max(1e-4, 0.5 * (tr + diff));
      final lam2 = math.max(1e-4, 0.5 * (tr - diff));
      f[26] = (lam1 - lam2) / (lam1 + lam2);
      f[27] = math.sqrt(lam2) / 16.0;
      f[28] = math.sqrt(lam1) / 16.0;
      final majorLen = math.max(2.0, 2.0 * math.sqrt(lam1));
      final bw = (maxMx - minMx + 1).toDouble();
      final bh = (maxMy - minMy + 1).toDouble();
      f[30] = mCount / (bw * bh);
      f[31] = math.min(1.0, (4.0 * mCount) / (math.pi * majorLen * majorLen));
    }

    const rays = <List<double>>[
      [1.0, 0.0],
      [0.70710678, 0.70710678],
      [0.0, 1.0],
      [-0.70710678, 0.70710678],
      [-1.0, 0.0],
      [-0.70710678, -0.70710678],
      [0.0, -1.0],
      [0.70710678, -0.70710678],
    ];
    final rayDists = Float32List(8);
    double minRay = 1.0, sumRay = 0.0;
    for (int ri = 0; ri < 8; ri++) {
      final dxr = rays[ri][0];
      final dyr = rays[ri][1];
      int dist = 0;
      for (int step = 1; step < 15; step++) {
        final sx = (15.5 + dxr * step).round();
        final sy = (15.5 + dyr * step).round();
        if (sx < 0 || sx >= 32 || sy < 0 || sy >= 32) break;
        final pi = sy * gridN + sx;
        if (yArr[pi] > math.max(0.45, lumaMean + 0.04) && satArr[pi] < 0.28) {
          dist = step;
        } else {
          final sx2 = (15.5 + dxr * (step + 1)).round();
          final sy2 = (15.5 + dyr * (step + 1)).round();
          if (sx2 >= 0 && sx2 < 32 && sy2 >= 0 && sy2 < 32) {
            final pi2 = sy2 * gridN + sx2;
            if (yArr[pi2] > math.max(0.48, lumaMean + 0.05) && satArr[pi2] < 0.26) {
              dist = step;
              continue;
            }
          }
          break;
        }
      }
      final dn = dist / 14.0;
      rayDists[ri] = dn;
      if (dn < minRay) minRay = dn;
      sumRay += dn;
    }
    f[36] = minRay;
    f[37] = sumRay / 8.0;

    double bestWire = 0.0;
    for (int ai = 0; ai < 4; ai++) {
      final pi = (ai + 2) % 4;
      final axExt = 0.5 * (rayDists[ai] + rayDists[ai + 4]);
      final perpExt = 0.5 * (rayDists[pi] + rayDists[pi + 4]);
      final wSc = math.max(0.0, axExt - perpExt * 1.3);
      if (wSc > bestWire) bestWire = wSc;
    }
    f[29] = bestWire;

    qm1 /= 256.0;
    qm2 /= 256.0;
    qm3 /= 256.0;
    qm4 /= 256.0;
    final qmMin = math.min(math.min(qm1, qm2), math.min(qm3, qm4));
    final qmMax = math.max(math.max(qm1, qm2), math.max(qm3, qm4));
    f[32] = qmMin / (qmMax + 0.01);

    final rSorted = Float32List.fromList(rowM)..sort();
    final cSorted = Float32List.fromList(colM)..sort();
    f[33] = rSorted[gridN - 1] - 0.5 * (rSorted[15] + rSorted[16]);
    f[34] = cSorted[gridN - 1] - 0.5 * (cSorted[15] + cSorted[16]);

    int mCore45 = 0, mCorners = 0;
    double satAll = 0, satCore = 0, satMid = 0, satOuter = 0;
    int warmOxide = 0, neutralPaper = 0, darkBoard = 0;
    double outerSpread = 0.0;

    for (int i = 0; i < totalPx; i++) {
      final mv = metal[i];
      if (_m.isCore45[i] && mv == 1) mCore45++;
      if (_m.isCorner[i] && mv == 1) mCorners++;

      final s = satArr[i];
      satAll += s;
      if (_m.isCore[i]) satCore += s;
      if (_m.isMid[i]) satMid += s;
      if (!_m.isCore[i] && !_m.isMid[i]) {
        satOuter += s;
        final rr = rArr[i], gg = gArr[i], bb = bArr[i];
        outerSpread += ((rr - gg).abs() + (gg - bb).abs() + (rr - bb).abs()) / 3.0;
      }

      if (_m.isIn60[i] && rArr[i] > gArr[i] + 0.07 && gArr[i] > bArr[i] + 0.05 && rArr[i] > bArr[i] + 0.14) {
        warmOxide++;
      }
      if (yArr[i] > 0.65 && grad[i] < 0.04 && s < 0.14) neutralPaper++;
      if (yArr[i] < 0.30) darkBoard++;
    }

    f[35] = (mCore45 / _m.core45Count + 0.01) / (mCorners / _m.cornerCount + 0.05);
    f[38] = satAll / totalPx;
    f[39] = satCore / _m.coreCount;
    f[40] = satOuter / _m.outerCount;
    f[41] = f[40] - f[39];
    f[42] = warmOxide / _m.in60Count;
    f[43] = neutralPaper / totalPx;
    f[44] = darkBoard / totalPx;
    f[45] = outerSpread / _m.outerCount;
    f[46] = math.min(w, h) / math.max(1, math.max(w, h));
    f[47] = (satMid / _m.midCount) - f[39];

    for (int i = 0; i < featureCount; i++) {
      if (f[i].isNaN || f[i].isInfinite) f[i] = 0.0;
    }
    return f;
  }
}

class _Masks {
  final Float32List radius = Float32List(1024);
  final List<bool> isCore = List<bool>.filled(1024, false);
  final List<bool> isMid = List<bool>.filled(1024, false);
  final List<bool> isIn60 = List<bool>.filled(1024, false);
  final List<bool> isIn65 = List<bool>.filled(1024, false);
  final List<bool> isIn75 = List<bool>.filled(1024, false);
  final List<bool> isCore45 = List<bool>.filled(1024, false);
  final List<bool> isCore28 = List<bool>.filled(1024, false);
  final List<bool> isRingDonut = List<bool>.filled(1024, false);
  final List<bool> isCenter18 = List<bool>.filled(1024, false);
  final List<bool> isCorner = List<bool>.filled(1024, false);

  late final int coreCount;
  late final int midCount;
  late final int outerCount;
  late final int in60Count;
  late final int in65Count;
  late final int core45Count;
  late final int core28Count;
  late final int ringDonutCount;
  late final int center18Count;
  late final int cornerCount;

  _Masks() {
    int cCore = 0, cMid = 0, cOut = 0, c60 = 0, c65 = 0, c45 = 0, c28 = 0, cRing = 0, c18 = 0, cCrn = 0;
    for (int y = 0; y < 32; y++) {
      final dy = (y - 15.5) / 15.5;
      for (int x = 0; x < 32; x++) {
        final dx = (x - 15.5) / 15.5;
        final r = math.sqrt(dx * dx + dy * dy);
        final i = y * 32 + x;
        radius[i] = r;
        if (r <= 0.30) {
          isCore[i] = true;
          cCore++;
        } else if (r <= 0.62) {
          isMid[i] = true;
          cMid++;
        } else {
          cOut++;
        }
        if (r <= 0.60) {
          isIn60[i] = true;
          c60++;
        }
        if (r <= 0.65) {
          isIn65[i] = true;
          c65++;
        }
        if (r <= 0.75) isIn75[i] = true;
        if (r <= 0.45) {
          isCore45[i] = true;
          c45++;
        }
        if (r <= 0.28) {
          isCore28[i] = true;
          c28++;
        }
        if (r >= 0.25 && r <= 0.50) {
          isRingDonut[i] = true;
          cRing++;
        }
        if (r <= 0.18) {
          isCenter18[i] = true;
          c18++;
        }
        if (r > 0.88) {
          isCorner[i] = true;
          cCrn++;
        }
      }
    }
    coreCount = cCore;
    midCount = cMid;
    outerCount = cOut;
    in60Count = c60;
    in65Count = c65;
    core45Count = c45;
    core28Count = c28;
    ringDonutCount = cRing;
    center18Count = c18;
    cornerCount = cCrn;
  }
}

/// Jaringan Saraf Tiruan Pure-Dart (3-Layer MLP: 48 -> 160 -> 80 -> 7)
class SoldyMlpNet {
  final int inDim;
  final int h1;
  final int h2;
  final int outDim;
  final Float32List w1;
  final Float32List b1;
  final Float32List w2;
  final Float32List b2;
  final Float32List w3;
  final Float32List b3;

  const SoldyMlpNet({
    required this.inDim,
    required this.h1,
    required this.h2,
    required this.outDim,
    required this.w1,
    required this.b1,
    required this.w2,
    required this.b2,
    required this.w3,
    required this.b3,
  });

  factory SoldyMlpNet.fromJson(Map<String, dynamic> m) {
    Float32List flatten2D(List<dynamic> mat) {
      final rows = mat.length;
      final cols = (mat[0] as List).length;
      final out = Float32List(rows * cols);
      int k = 0;
      for (final row in mat) {
        for (final v in (row as List)) {
          out[k++] = (v as num).toDouble();
        }
      }
      return out;
    }

    Float32List toVec(List<dynamic> vec) => Float32List.fromList(vec.map((e) => (e as num).toDouble()).toList());

    final rawW1 = m['W1'] as List;
    final rawW2 = m['W2'] as List;
    final rawW3 = m['W3'] as List;
    return SoldyMlpNet(
      inDim: rawW1.length,
      h1: (rawW1[0] as List).length,
      h2: (rawW2[0] as List).length,
      outDim: (rawW3[0] as List).length,
      w1: flatten2D(rawW1),
      b1: toVec(m['b1'] as List),
      w2: flatten2D(rawW2),
      b2: toVec(m['b2'] as List),
      w3: flatten2D(rawW3),
      b3: toVec(m['b3'] as List),
    );
  }

  Float32List predictProba(Float32List xz) {
    final a1 = Float32List(h1);
    for (int j = 0; j < h1; j++) {
      double acc = b1[j];
      int off = j;
      for (int i = 0; i < inDim; i++) {
        acc += xz[i] * w1[off];
        off += h1;
      }
      a1[j] = acc > 0.0 ? acc : 0.0;
    }

    final a2 = Float32List(h2);
    for (int j = 0; j < h2; j++) {
      double acc = b2[j];
      int off = j;
      for (int i = 0; i < h1; i++) {
        acc += a1[i] * w2[off];
        off += h2;
      }
      a2[j] = acc > 0.0 ? acc : 0.0;
    }

    final logits = Float32List(outDim);
    double maxLogit = -1e9;
    for (int j = 0; j < outDim; j++) {
      double acc = b3[j];
      int off = j;
      for (int i = 0; i < h2; i++) {
        acc += a2[i] * w3[off];
        off += outDim;
      }
      logits[j] = acc;
      if (acc > maxLogit) maxLogit = acc;
    }

    final probs = Float32List(outDim);
    double sumExp = 0.0;
    for (int j = 0; j < outDim; j++) {
      final ex = math.exp((logits[j] - maxLogit).clamp(-30.0, 30.0));
      probs[j] = ex;
      sumExp += ex;
    }
    for (int j = 0; j < outDim; j++) {
      probs[j] /= sumExp;
    }
    return probs;
  }
}

/// Metadata & Bobot Model Inferensi Solder (`Soldy-Net-V6` Hybrid + Fallback V5)
class SolderModelMetadata {
  final String modelName;
  final String datasetSource;
  final String trainingDate;
  final List<String> classes;
  final List<double> featureMean;
  final List<double> featureStd;
  final List<List<double>> centroids;
  final List<List<double>>? linearWeights;
  final List<double>? linearBiases;

  // Soldy-Net-V6 Hybrid MLP + ExtraTrees Payload
  final bool isV6;
  final double mlpWeight;
  final Float32List? v6Mean;
  final Float32List? v6Std;
  final List<SoldyMlpNet>? mlps;
  final List<List<List<double>>>? trees;

  static SolderModelMetadata? _cachedV6;

  const SolderModelMetadata({
    required this.modelName,
    required this.datasetSource,
    required this.trainingDate,
    required this.classes,
    required this.featureMean,
    required this.featureStd,
    required this.centroids,
    this.linearWeights,
    this.linearBiases,
    this.isV6 = false,
    this.mlpWeight = 0.80,
    this.v6Mean,
    this.v6Std,
    this.mlps,
    this.trees,
  });

  factory SolderModelMetadata.fromJson(Map<String, dynamic> json) {
    if (json['mlps'] != null && json['trees'] != null) {
      final meanList = (json['scaler_mean'] as List).map((e) => (e as num).toDouble()).toList();
      final stdList = (json['scaler_std'] as List).map((e) => (e as num).toDouble()).toList();
      final mlpNets = (json['mlps'] as List).map((m) => SoldyMlpNet.fromJson(m as Map<String, dynamic>)).toList();
      final treeList = (json['trees'] as List).map((t) {
        return (t as List).map((nd) {
          return (nd as List).map((v) => (v as num).toDouble()).toList();
        }).toList();
      }).toList();

      return SolderModelMetadata(
        modelName: json['model_name'] as String? ?? AppConstants.defaultModelVersion,
        datasetSource: 'Curated V6 Multi-Source THT + SMD (23,185+ crops, 7 classes)',
        trainingDate: '2026-11-25',
        classes: (json['classes'] as List).map((e) => e.toString()).toList(),
        featureMean: meanList,
        featureStd: stdList,
        centroids: const [],
        isV6: true,
        mlpWeight: (json['mlp_weight'] as num?)?.toDouble() ?? 0.80,
        v6Mean: Float32List.fromList(meanList),
        v6Std: Float32List.fromList(stdList),
        mlps: mlpNets,
        trees: treeList,
      );
    }

    final hasLinear = json['weights'] != null && json['biases'] != null;
    final List<double> fMean = ((json['feature_mean'] ?? json['scaler_mean']) as List<dynamic>? ?? List.filled(11, 0.0))
        .map((e) => (e as num).toDouble())
        .toList();
    final List<double> fStd = ((json['feature_std'] ?? json['scaler_std']) as List<dynamic>? ?? List.filled(11, 1.0))
        .map((e) => (e as num).toDouble())
        .toList();

    return SolderModelMetadata(
      modelName: json['model_name'] as String? ?? 'QC-Solder-Model',
      datasetSource: json['dataset_source'] as String? ?? 'Embedded',
      trainingDate: json['training_date'] as String? ?? '',
      classes: (json['classes'] as List<dynamic>).map((e) => e.toString()).toList(),
      featureMean: fMean,
      featureStd: fStd,
      centroids: json['centroids'] != null
          ? (json['centroids'] as List<dynamic>).map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList()
          : const [],
      linearWeights: hasLinear
          ? (json['weights'] as List<dynamic>).map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList()
          : null,
      linearBiases: hasLinear ? (json['biases'] as List<dynamic>).map((e) => (e as num).toDouble()).toList() : null,
    );
  }

  /// Metadata tertanam sinkron (dipakai saat sinkron tanpa async init). Jika V6 sudah di-cache, gunakan V6.
  static SolderModelMetadata defaultEmbedded() {
    if (_cachedV6 != null) return _cachedV6!;
    final f = File('assets/models/soldy_v6_model.json');
    if (f.existsSync()) {
      try {
        _cachedV6 = SolderModelMetadata.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
        return _cachedV6!;
      } catch (_) {}
    }

    return const SolderModelMetadata(
      modelName: 'Soldy-Fallback-Linear',
      datasetSource: 'Embedded Fallback Linear Model',
      trainingDate: '2026-11-25',
      classes: ['D1_BRIDGE', 'D3_INSUFFICIENT', 'D4_EXCESS', 'PASS_NORMAL'],
      featureMean: [152.931797, 50.858989, 224.088574, 83.275021, 0.341443, 0.088547, 10.677829, 10.506435, 0.145675, 0.77938, 17.56125],
      featureStd: [40.483415, 19.307503, 40.916364, 41.318964, 0.258709, 0.16505, 5.479325, 4.92938, 0.155833, 0.181506, 36.29816],
      centroids: [],
      linearWeights: [
        [-0.312, 0.562, 0.155, -0.354, 0.273, -0.453, 0.276, 0.064, 0.371, -0.922, 0.011],
        [-0.415, -0.335, -0.029, -0.409, -0.172, 0.588, -0.589, 0.119, 1.158, 0.253, 0.068],
        [0.440, 0.144, 0.296, 0.451, -0.144, 0.123, 0.301, 0.025, -0.946, 0.246, -0.369],
        [0.287, -0.371, -0.422, 0.312, 0.043, -0.258, 0.012, -0.208, -0.583, 0.423, 0.289],
      ],
      linearBiases: [0.008, -0.170, 0.044, 0.117],
    );
  }

  /// Muat model Soldy-Net-V6 utama dari Flutter asset bundle / disk, jatuh ke defaultEmbedded jika gagal.
  static Future<SolderModelMetadata> load({String? customPath}) async {
    if (_cachedV6 != null && customPath == null) return _cachedV6!;
    try {
      if (customPath != null && File(customPath).existsSync()) {
        final content = await File(customPath).readAsString();
        final loaded = SolderModelMetadata.fromJson(jsonDecode(content) as Map<String, dynamic>);
        if (loaded.isV6) _cachedV6 = loaded;
        return loaded;
      }

      try {
        final v6Str = await rootBundle.loadString('assets/models/soldy_v6_model.json');
        final loaded = SolderModelMetadata.fromJson(jsonDecode(v6Str) as Map<String, dynamic>);
        _cachedV6 = loaded;
        return loaded;
      } catch (_) {}

      final localV6 = File('assets/models/soldy_v6_model.json');
      if (localV6.existsSync()) {
        final loaded = SolderModelMetadata.fromJson(jsonDecode(await localV6.readAsString()) as Map<String, dynamic>);
        _cachedV6 = loaded;
        return loaded;
      }
    } catch (_) {}

    return defaultEmbedded();
  }
}

/// Hasil prediksi lengkap Soldy AI untuk satu titik kandidat
class SolderPrediction {
  final String result;
  final int? defectTypeId;
  final String defectCode;
  final double confidence;
  final Map<String, double> classProbabilities;
  final bool isSolderJoint;
  final double nonSolderScore;

  const SolderPrediction({
    required this.result,
    required this.defectTypeId,
    required this.defectCode,
    required this.confidence,
    required this.classProbabilities,
    this.isSolderJoint = true,
    this.nonSolderScore = 0.0,
  });
}

/// Mesin Inferensi Utama SolderLab (Soldy-Net-V6 Hybrid MLP + ExtraTrees Ensemble)
class SolderModelEngine {
  final SolderModelMetadata metadata;

  SolderModelEngine({required this.metadata});

  /// Klasifikasi sambungan solder pada seluruh jenis papan PCB memakai Soldy-Net-V6
  /// atau model linear fallback bila bobot V6 tidak tersedia.
  SolderPrediction predict(
    img.Image patch,
    double confidenceThreshold, {
    String boardType = AppConstants.boardGeneralPcb,
  }) {
    if (metadata.isV6 && metadata.v6Mean != null && metadata.v6Std != null && metadata.mlps != null && metadata.trees != null) {
      return _predictSoldyV6(patch, confidenceThreshold);
    }
    return _predictLinearFallback(patch, confidenceThreshold);
  }

  SolderPrediction _predictSoldyV6(img.Image patch, double confidenceThreshold) {
    final rawFeat = SoldyV6FeatureExtractor.extract(patch);
    final mean = metadata.v6Mean!;
    final std = metadata.v6Std!;
    final xz = Float32List(SoldyV6FeatureExtractor.featureCount);
    for (int i = 0; i < SoldyV6FeatureExtractor.featureCount; i++) {
      xz[i] = (rawFeat[i] - mean[i]) / std[i];
    }

    final numClasses = metadata.classes.length;
    final pMlp = Float64List(numClasses);
    for (final mlp in metadata.mlps!) {
      final pr = mlp.predictProba(xz);
      for (int c = 0; c < numClasses; c++) {
        pMlp[c] += pr[c];
      }
    }
    final invMlp = 1.0 / metadata.mlps!.length;
    for (int c = 0; c < numClasses; c++) {
      pMlp[c] *= invMlp;
    }

    final pRf = Float64List(numClasses);
    final trees = metadata.trees!;
    for (final nodes in trees) {
      int idx = 0;
      while (true) {
        final nd = nodes[idx];
        if (nd[0] >= 0.5) {
          for (int c = 0; c < numClasses; c++) {
            pRf[c] += nd[1 + c];
          }
          break;
        }
        final fi = nd[1].toInt();
        final thr = nd[2];
        idx = (rawFeat[fi] <= thr) ? nd[3].toInt() : nd[4].toInt();
      }
    }
    final invTrees = 1.0 / trees.length;
    for (int c = 0; c < numClasses; c++) {
      pRf[c] *= invTrees;
    }

    final wMlp = metadata.mlpWeight;
    final wRf = 1.0 - wMlp;
    final probsMap = <String, double>{};
    int bestSolderIdx = 0;
    double bestSolderProb = -1.0;
    double nonSolderProb = 0.0;

    for (int c = 0; c < numClasses; c++) {
      final p = wMlp * pMlp[c] + wRf * pRf[c];
      final cname = metadata.classes[c];
      probsMap[cname] = p;
      if (cname == AppConstants.defectNonSolder) {
        nonSolderProb = p;
      } else if (p > bestSolderProb) {
        bestSolderProb = p;
        bestSolderIdx = c;
      }
    }

    // Gerbang mayoritas non-solder (>= 0.52): hindari pembelahan suara 6 kelas menolak titik solder asli
    final bool isNonSolder = nonSolderProb >= 0.52;
    if (isNonSolder) {
      return SolderPrediction(
        result: AppConstants.statusUncertain,
        defectTypeId: null,
        defectCode: AppConstants.defectNonSolder,
        confidence: nonSolderProb,
        classProbabilities: probsMap,
        isSolderJoint: false,
        nonSolderScore: nonSolderProb,
      );
    }

    final String predictedClass = metadata.classes[bestSolderIdx];
    final double solderMass = math.max(1e-6, 1.0 - nonSolderProb);
    final double bestProb = (bestSolderProb / solderMass).clamp(0.0, 1.0);

    String resultStatus;
    int? defectId;
    switch (predictedClass) {
      case AppConstants.defectPass:
        resultStatus = bestProb >= confidenceThreshold ? AppConstants.statusPass : AppConstants.statusUncertain;
        defectId = 1;
        break;
      case AppConstants.defectD1:
        resultStatus = bestProb >= confidenceThreshold ? AppConstants.statusFail : AppConstants.statusUncertain;
        defectId = 2;
        break;
      case AppConstants.defectD2:
        resultStatus = bestProb >= confidenceThreshold ? AppConstants.statusFail : AppConstants.statusUncertain;
        defectId = 3;
        break;
      case AppConstants.defectD3:
        resultStatus = bestProb >= confidenceThreshold ? AppConstants.statusFail : AppConstants.statusUncertain;
        defectId = 4;
        break;
      case AppConstants.defectD4:
        resultStatus = bestProb >= confidenceThreshold ? AppConstants.statusFail : AppConstants.statusUncertain;
        defectId = 5;
        break;
      case AppConstants.defectD5:
        resultStatus = bestProb >= confidenceThreshold ? AppConstants.statusFail : AppConstants.statusUncertain;
        defectId = 6;
        break;
      default:
        resultStatus = AppConstants.statusUncertain;
        defectId = null;
    }

    return SolderPrediction(
      result: resultStatus,
      defectTypeId: defectId,
      defectCode: predictedClass,
      confidence: bestProb,
      classProbabilities: probsMap,
      isSolderJoint: true,
      nonSolderScore: nonSolderProb,
    );
  }

  SolderPrediction _predictLinearFallback(img.Image patch, double confidenceThreshold) {
    final features = SolderFeatures.extract(patch);
    final rawVec = features.toVector();
    final zVec = List<double>.filled(11, 0.0);
    for (int i = 0; i < 11; i++) {
      final std = metadata.featureStd[i] > 1e-6 ? metadata.featureStd[i] : 1.0;
      zVec[i] = (rawVec[i] - metadata.featureMean[i]) / std;
    }

    final weights = metadata.linearWeights!;
    final biases = metadata.linearBiases!;
    final numClasses = metadata.classes.length;
    final logits = List<double>.filled(numClasses, 0.0);
    double maxLogit = -double.infinity;

    for (int c = 0; c < numClasses; c++) {
      double dot = biases[c];
      for (int i = 0; i < 11; i++) {
        dot += weights[c][i] * zVec[i];
      }
      logits[c] = dot;
      if (dot > maxLogit) maxLogit = dot;
    }

    final exps = List<double>.filled(numClasses, 0.0);
    double sumExp = 0.0;
    for (int c = 0; c < numClasses; c++) {
      final e = math.exp((logits[c] - maxLogit).clamp(-20.0, 20.0));
      exps[c] = e;
      sumExp += e;
    }

    final Map<String, double> probsMap = {};
    int bestIdx = 0;
    double bestProb = -1.0;
    for (int c = 0; c < numClasses; c++) {
      final prob = exps[c] / sumExp;
      probsMap[metadata.classes[c]] = prob;
      if (prob > bestProb) {
        bestProb = prob;
        bestIdx = c;
      }
    }

    final predictedClass = metadata.classes[bestIdx];
    final resultStatus = predictedClass == AppConstants.defectPass
        ? (bestProb >= confidenceThreshold ? AppConstants.statusPass : AppConstants.statusUncertain)
        : (bestProb >= confidenceThreshold ? AppConstants.statusFail : AppConstants.statusUncertain);

    final int? defectId = switch (predictedClass) {
      AppConstants.defectPass => 1,
      AppConstants.defectD1 => 2,
      AppConstants.defectD2 => 3,
      AppConstants.defectD3 => 4,
      AppConstants.defectD4 => 5,
      AppConstants.defectD5 => 6,
      _ => null,
    };

    return SolderPrediction(
      result: resultStatus,
      defectTypeId: defectId,
      defectCode: predictedClass,
      confidence: bestProb,
      classProbabilities: probsMap,
      isSolderJoint: true,
      nonSolderScore: 0.0,
    );
  }
}
