import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _launchUrl('https://anystupididea.com'),
            child: Text(
              '\u00a9 ${DateTime.now().year} Any Stupid Idea',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl('https://anystupididea.com/privacy.html'),
                child: Text(
                  'Privacy',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
              Text('  \u00b7  ', style: TextStyle(fontSize: 11, color: muted)),
              GestureDetector(
                onTap: () => _launchUrl('https://anystupididea.com/terms.html'),
                child: Text(
                  'Terms',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
