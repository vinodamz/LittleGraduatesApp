import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

class LgAvatar extends StatelessWidget {
  const LgAvatar({required this.name, this.radius = 22, super.key});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash + c) % LgColors.avatarBackgrounds.length;
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: LgColors.avatarBackgrounds[hash],
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: LgColors.avatarForegrounds[hash],
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}

class LgStatusPill extends StatelessWidget {
  const LgStatusPill({
    required this.label,
    required this.foreground,
    required this.background,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class LgSectionTitle extends StatelessWidget {
  const LgSectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class LgEmptyState extends StatelessWidget {
  const LgEmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: LgColors.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, color: LgColors.accent, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: LgColors.muted, height: 1.4),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class LgNotice extends StatelessWidget {
  const LgNotice({
    required this.message,
    required this.foreground,
    required this.background,
    this.icon,
    super.key,
  });

  final String message;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(message, style: TextStyle(color: foreground, height: 1.35, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
