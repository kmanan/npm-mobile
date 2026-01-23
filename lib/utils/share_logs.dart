import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/log_service.dart';

const String _githubIssuesUrl = 'https://github.com/kmanan/npm-mobile/issues';

Future<void> shareLogs(BuildContext context) async {
  final logService = LogService();
  final logs = await logService.getLogs();

  if (logs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No logs available to share'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  final logsText = logs.join('\n');

  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Share Logs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy to Clipboard'),
            subtitle: const Text('Paste logs anywhere you need'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: logsText));
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logs copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share via...'),
            subtitle: const Text('Send logs to yourself or others'),
            onTap: () async {
              Navigator.pop(context);
              await Share.share(
                logsText,
                subject: 'Nginx Mobile Dashboard Auth Logs',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Open GitHub Issues'),
            subtitle: const Text('Report a bug with your logs'),
            onTap: () async {
              Navigator.pop(context);
              final uri = Uri.parse(_githubIssuesUrl);
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Logs copied! Paste them in your GitHub issue.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                  // Also copy logs to clipboard for easy pasting
                  await Clipboard.setData(ClipboardData(text: logsText));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not open GitHub: $e'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
