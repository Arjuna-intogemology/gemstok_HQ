import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../blogs/blog_api.dart';
import '../settings/key_store.dart';

/// Decides whether HQ is locked.
///
/// Locked when:  the app starts · the Mac sleeps or the screen locks (macOS tells us
/// through the 'gemstok_hq/lock' channel, see macos/Runner/MainFlutterWindow.swift) ·
/// nobody touched the mouse or keyboard for [idleLimit] · you press "Lock now".
/// Unlocked only by Touch ID (macOS offers the Mac password if Touch ID fails).
class LockController extends ChangeNotifier {
  LockController() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'lockNow') lock();
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _checkIdle());
  }

  static const idleLimit = Duration(minutes: 5);
  static const _channel = MethodChannel('gemstok_hq/lock');

  final _auth = LocalAuthentication();
  Timer? _ticker;
  DateTime _lastActivity = DateTime.now();
  bool _locked = true;
  bool _busy = false;
  bool _autoAsked = false; // Touch ID already offered by itself since HQ locked / came to the front
  String? _message;

  bool get locked => _locked;
  bool get busy => _busy;

  /// Plain-English reason the last unlock didn't work (null = nothing to say).
  String? get message => _message;

  /// Called when the lock screen shows or HQ comes back to the front: asks Touch ID once by itself.
  /// If you cancel, it waits for the button (or the next time HQ comes to the front) — no nagging.
  void autoUnlock() {
    if (!_locked || _busy || _autoAsked) return;
    // Only when HQ is the app in front. Locked in the background (idle, while you use other apps)
    // → stay quiet; Touch ID asks when you come back to HQ.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _autoAsked = true;
    unlock();
  }

  DateTime _promptEnded = DateTime.fromMillisecondsSinceEpoch(0);

  /// HQ came back to the front → allowed to ask by itself again.
  /// Not within 3 s of a prompt closing: the Touch ID sheet itself makes HQ leave and return
  /// to the front, and that must not re-ask right after you pressed Cancel.
  void allowAutoAgain() {
    if (DateTime.now().difference(_promptEnded) > const Duration(seconds: 3)) _autoAsked = false;
  }

  Future<void> unlock() async {
    if (_busy) return;
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final ok = await _auth.authenticate(localizedReason: 'unlock Gemstok HQ');
      if (ok) {
        _locked = false;
        _lastActivity = DateTime.now();
      } else {
        _message = 'Not unlocked. Try again.';
      }
    } catch (e) {
      // e.g. Touch ID not set up on this Mac. The text holds no secrets.
      _message = 'Touch ID could not run: $e';
    } finally {
      _busy = false;
      _promptEnded = DateTime.now();
      notifyListeners();
    }
  }

  void lock() {
    if (_locked) return;
    _locked = true;
    _autoAsked = false;
    KeyStore.forget(); // passwords leave memory when HQ locks
    BlogApi.forget(); // and the blog admin sign-in
    notifyListeners();
  }

  /// Called on every mouse move / click / scroll (see main.dart) and key press.
  void activity() => _lastActivity = DateTime.now();

  bool _onKey(KeyEvent event) {
    activity();
    return false; // never swallow the key
  }

  void _checkIdle() {
    if (!_locked && DateTime.now().difference(_lastActivity) >= idleLimit) lock();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
