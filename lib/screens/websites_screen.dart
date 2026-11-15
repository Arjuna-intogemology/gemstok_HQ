import 'package:flutter/material.dart';

import '../services/services_data.dart';
import '../services/services_view.dart';

/// Websites: visitors, page views and blocked threats per site (Cloudflare).
class WebsitesScreen extends StatelessWidget {
  const WebsitesScreen({super.key, required this.services});
  final ServicesData services;

  @override
  Widget build(BuildContext context) => ServicesFrame(
        title: 'Websites',
        subtitle: 'Every site on your Cloudflare account. Campaign clicks are under Leads.',
        services: services,
        ids: const ['cloudflare'],
        children: [WebsiteTraffic(services: services)],
      );
}
