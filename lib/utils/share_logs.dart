import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/log_service.dart';

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

  final emailBody = logs.join('\n');
  final Uri emailLaunchUri = Uri(
    scheme: 'mailto',
    path: 'manan@outlook.com',
    query: encodeQueryParameters({
      'subject': 'Nginx Mobile Dashboard Auth Logs',
      'body': emailBody,
    }),
  );

  try {
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No email app found'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing logs: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

String? encodeQueryParameters(Map<String, String> params) {
  return params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
