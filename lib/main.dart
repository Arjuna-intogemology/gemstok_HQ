import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'keepalive/keep_alive.dart';
import 'lock/lock_controller.dart';
import 'lock/lock_screen.dart';
import 'shell/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep alive runs for the whole app, also while HQ is locked (it only counts rows, shows nothing).
  runApp(HqApp(lock: LockController(), keepAlive: HqKeepAlive()));
}

class HqApp extends StatelessWidget {
  const HqApp({super.key, required this.lock, required this.keepAlive});

  final LockController lock;
  final HqKeepAlive keepAlive;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemstok HQ',
      debugShowCheckedModeBanner: false,
      theme: hqTheme(),
      // Any mouse movement / click / scroll counts as "still here" for the 5-minute lock.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => lock.activity(),
        onPointerHover: (_) => lock.activity(),
        onPointerSignal: (_) => lock.activity(),
        child: child,
      ),
      home: ListenableBuilder(
        listenable: lock,
        // Locked → only the lock screen exists. Unlocking builds the shell fresh;
        // locking throws it (and everything loaded in it) away.
        builder: (context, _) => lock.locked ? LockScreen(lock: lock) : HqShell(lock: lock, keepAlive: keepAlive),
      ),
    );
  }
}
