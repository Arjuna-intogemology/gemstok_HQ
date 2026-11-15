import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'campaign_store.dart';

/// Makes a print-ready PNG: white background, the QR code, and two lines of text under it.
/// Saved to  gemstok_hq/leads/qr/<tag>.png  (1200 × 1450 px — sharp at A6 and bigger).
class QrExport {
  static const _w = 1200.0;
  static const _h = 1450.0;
  static const _pad = 110.0;

  static Future<File> savePng(Campaign c, {required String title, String? byLine}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

    final painter = QrPainter(
      data: c.qrLink,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
    const qrSize = _w - 2 * _pad;
    canvas.save();
    canvas.translate(_pad, _pad);
    painter.paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();

    void text(String s, double y, double size, FontWeight weight, Color colour) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'Jost', fontSize: size, fontWeight: weight, color: colour),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _w - 2 * _pad);
      tp.paint(canvas, Offset((_w - tp.width) / 2, y));
    }

    text(title, _pad + qrSize + 40, 64, FontWeight.w600, Colors.black);
    text(c.link.replaceFirst('https://', ''), _pad + qrSize + 130, 36, FontWeight.w400, const Color(0xFF555555));
    if (byLine != null && byLine.isNotEmpty) {
      text(byLine, _pad + qrSize + 185, 40, FontWeight.w500, const Color(0xFF333333));
    }

    final image = await recorder.endRecording().toImage(_w.toInt(), _h.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${CampaignStore.folder}/qr');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${c.tag}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file;
  }

  /// Opens Finder with the file selected.
  static Future<void> showInFinder(File f) => Process.run('open', ['-R', f.path]);
}
