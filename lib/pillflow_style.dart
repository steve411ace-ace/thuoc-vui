import 'dart:ui';

import 'package:flutter/material.dart';

import 'strings.dart';

const pillEmerald = Color(0xFF10B981);
const pillSky = Color(0xFF0EA5E9);
const pillOrange = Color(0xFFF97316);
const pillAmber = Color(0xFFFBBF24);
const pillSlate = Color(0xFFCBD5E1);
const pillTeal = Color(0xFF0D9488);
const pillDarkTeal = Color(0xFF2DD4BF);

LinearGradient pillGradient(ColorScheme scheme) {
  final brand = scheme.primary;
  final isTeal = brand == pillTeal || brand == pillDarkTeal;
  final middle = isTeal
      ? pillTeal
      : Color.alphaBlend(
          Colors.black.withAlpha(brand.computeLuminance() > .45 ? 110 : 0),
          brand);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isTeal
        ? const [Color(0xFF0F766E), pillTeal, pillSky]
        : [
            Color.alphaBlend(Colors.black26, middle),
            middle,
            Color.lerp(middle, pillSky, .4)!
          ],
  );
}

BoxDecoration pillPanel(ColorScheme scheme, {double radius = 20}) =>
    BoxDecoration(
      color: scheme.surface,
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(radius),
    );

class PillGlass extends StatelessWidget {
  const PillGlass({super.key, required this.child, this.radius = 24});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = pillPanel(scheme, radius: radius).copyWith(
      color: scheme.surface.withAlpha(
        scheme.brightness == Brightness.dark ? 219 : 214,
      ),
    );
    return ClipRRect(
      borderRadius: decoration.borderRadius!,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(decoration: decoration, child: child),
      ),
    );
  }
}

String pillWeekday(DateTime date) => weekdayShort(date.weekday);

bool pillTaken(String? status) => status == 'taken' || status == 'late';

Color pillAdherenceDot(int taken, int total) {
  if (total == 0) return pillSlate;
  if (taken == total) return pillEmerald;
  return taken * 2 >= total ? pillAmber : pillSlate;
}

class PillShapeIcon extends StatelessWidget {
  const PillShapeIcon(this.shape,
      {super.key, required this.color, this.size = 44});

  final String shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withAlpha(36),
          borderRadius: BorderRadius.circular(16),
        ),
        child: PillShapeGlyph(shape, color: color),
      );
}

class PillShapeGlyph extends StatelessWidget {
  const PillShapeGlyph(this.shape, {super.key, required this.color});

  final String shape;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(24),
        painter: _PillShapePainter(shape, color),
      );
}

class _PillShapePainter extends CustomPainter {
  const _PillShapePainter(this.shape, this.color);

  final String shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (shape) {
      case 'tablet':
        canvas.drawCircle(const Offset(12, 12), 8, ink);
        canvas.drawLine(const Offset(7.5, 16.5), const Offset(16.5, 7.5), ink);
      case 'drop':
        canvas.drawPath(
          Path()
            ..moveTo(12, 4)
            ..cubicTo(10, 6, 6, 11, 6, 14)
            ..cubicTo(6, 22, 18, 22, 18, 14)
            ..cubicTo(18, 11, 14, 6, 12, 4)
            ..close(),
          ink,
        );
      case 'pack':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(5, 4, 14, 16),
              const Radius.circular(3),
            ),
            ink);
        canvas.drawLine(const Offset(9, 12), const Offset(15, 12), ink);
        canvas.drawLine(const Offset(12, 9), const Offset(12, 15), ink);
      default:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-0.785398);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-10, -5, 20, 10),
              const Radius.circular(5),
            ),
            ink);
        canvas.drawLine(const Offset(0, -5), const Offset(0, 5), ink);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PillShapePainter oldDelegate) =>
      shape != oldDelegate.shape || color != oldDelegate.color;
}
