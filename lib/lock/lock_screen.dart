import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'lock_controller.dart';

/// Shown whenever HQ is locked. Nothing else is built behind it.
/// Touch ID is asked for by itself when this screen appears and whenever HQ comes back to the front;
/// the button is only a backup (e.g. after you cancelled).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});

  final LockController lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // after the first frame, so the window is on screen when macOS shows the Touch ID sheet
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.lock.autoUnlock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.lock.allowAutoAgain();
      widget.lock.autoUnlock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/logo/hq_logo.png', width: 96, height: 96),
              ),
              const SizedBox(height: 18),
              Text('GEMSTOK HQ', style: jost(26, weight: 600)),
              const SizedBox(height: 6),
              Text(lock.busy ? 'Touch the sensor to unlock.' : 'Private. Locked.',
                  style: jost(14, color: HqColors.muted)),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: lock.busy ? null : lock.unlock,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(lock.busy ? 'Waiting for Touch ID…' : 'Unlock with Touch ID',
                      style: jost(15, weight: 500)),
                ),
              ),
              if (lock.message != null) ...[
                const SizedBox(height: 16),
                Text(lock.message!, textAlign: TextAlign.center, style: jost(13, color: HqColors.bad)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
