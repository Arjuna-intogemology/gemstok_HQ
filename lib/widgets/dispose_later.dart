import 'package:flutter/foundation.dart';

/// Text boxes used inside a dialog: dispose them only after the dialog's closing animation is over.
/// (Disposing right after `await showDialog(...)` crashes — the dialog is still on screen for a moment.)
void disposeLater(Iterable<ChangeNotifier> items) {
  final list = items.toList();
  Future.delayed(const Duration(milliseconds: 800), () {
    for (final c in list) {
      c.dispose();
    }
  });
}
