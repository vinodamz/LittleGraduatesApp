import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://thelittlegraduates.in/privacy-policy/';

Future<void> openPrivacyPolicy(BuildContext context) async {
  final opened = await launchUrl(
    Uri.parse(privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the privacy policy. Visit https://thelittlegraduates.in/privacy-policy/',
        ),
      ),
    );
  }
}

class PrivacyPolicyButton extends StatelessWidget {
  const PrivacyPolicyButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => openPrivacyPolicy(context),
    child: const Text('Privacy policy'),
  );
}

Future<bool> requestTripLocationConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share location during this trip?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Little Graduates collects your precise location to track the school cab, estimate arrivals and let the school and families follow the active trip. Location is sent to the school transport system even when the app is in the background or your phone screen is off. Tracking stops when the trip is finished or cancelled.',
            ),
            PrivacyPolicyButton(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    ) ??
    false;
