import 'package:flutter/material.dart';

import '../services/services_data.dart';
import '../services/services_view.dart';
import '../widgets/screen_frame.dart';

/// Downloads: iPhone downloads / updates / reviews (App Store Connect) and
/// Android installs / active devices / reviews (Google Play).
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.services});
  final ServicesData services;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) => ServicesFrame(
        title: 'Downloads',
        subtitle: 'From App Store Connect and Google Play, once their keys are in Settings → Other services.',
        services: widget.services,
        ids: const ['appstore', 'googleplay'],
        children: [
          const SizedBox(height: 12),
          Choice<int>(
            options: const {7: '7 days', 30: '30 days', 90: '90 days'},
            value: _days,
            onChanged: (v) => setState(() => _days = v),
          ),
          StoresAndAds(services: widget.services, days: _days, downloads: true),
        ],
      );
}
