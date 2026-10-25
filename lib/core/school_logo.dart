import 'package:flutter/material.dart';

/// The original, unmodified logo published on the school's website.
class SchoolLogo extends StatelessWidget {
  const SchoolLogo({this.size = 48, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'The Little Graduates logo',
  );
}
