import 'dart:math';
import 'package:flutter/material.dart';

enum PipMood { happy, worried, celebrate }

/// Pip: viên thuốc tròn trịa vẽ bằng CustomPainter, nảy lên nhè nhẹ.
class PipWidget extends StatefulWidget {
  final double size;
  final PipMood mood;
  const PipWidget({super.key, this.size = 120, this.mood = PipMood.happy});

  @override
  State<PipWidget> createState() => _PipWidgetState();
}

class _PipWidgetState extends State<PipWidget> with TickerProviderStateMixin {
  late final AnimationController _bounce;
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    // Chớp mắt định kỳ: mỗi chu kỳ 3.2s, nháy trong ~12% cuối chu kỳ.
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _bounce.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bounce, _blink]),
      builder: (context, child) {
        final isCelebrate = widget.mood == PipMood.celebrate;
        final bounce = isCelebrate
            ? sin(_bounce.value * pi * 2) * 10
            : sin(_bounce.value * pi) * 6;
        final tilt = sin(_bounce.value * pi * 2) * 0.05;
        final blink = widget.mood == PipMood.happy && _blink.value > 0.88;
        return Transform.translate(
          offset: Offset(0, -bounce.abs()),
          child: Transform.rotate(
            angle: tilt,
            child: CustomPaint(
              size: Size(widget.size * 100 / 118, widget.size),
              painter: _PipPainter(widget.mood, blink: blink),
            ),
          ),
        );
      },
    );
  }
}

class _PipPainter extends CustomPainter {
  final PipMood mood;
  final bool blink;
  _PipPainter(this.mood, {required this.blink});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / 100, size.height / 118);
    canvas.save();
    canvas.translate(
        (size.width - 100 * scale) / 2, (size.height - 118 * scale) / 2);
    canvas.scale(scale);

    const body = Rect.fromLTRB(6, 6, 94, 112);
    final capsule = RRect.fromRectAndRadius(body, const Radius.circular(44));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 113), width: 50, height: 5),
      Paint()
        ..color = const Color(0x2929433D)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.1),
    );
    canvas.drawRRect(
        capsule,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE98A), Color(0xFFFFD93D), Color(0xFFF3BD31)],
            stops: [0, 0.48, 1],
          ).createShader(body));
    canvas.save();
    canvas.clipRRect(capsule);
    canvas.drawRect(
        const Rect.fromLTRB(6, 6, 50, 112),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFFBFCFD), Color(0xFFE9EFF1)],
            stops: [0, 0.58, 1],
          ).createShader(const Rect.fromLTRB(6, 6, 50, 112)));
    canvas.restore();
    canvas.drawRRect(
        capsule.deflate(1.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = const Color(0x4D8E7440));

    final gloss = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5
      ..color = const Color(0x9EFFFFFF);
    canvas.drawPath(
        Path()
          ..moveTo(70, 15)
          ..cubicTo(78, 19, 82, 27, 82, 36),
        gloss);
    gloss
      ..strokeWidth = 2.2
      ..color = const Color(0xD1FFFFFF);
    canvas.drawPath(
        Path()
          ..moveTo(12, 37)
          ..cubicTo(12, 24, 19, 14, 29, 10),
        gloss);

    final blush = Paint()..color = const Color(0x8CF48E9A);
    canvas.drawCircle(const Offset(21, 59), 6.5, blush);
    canvas.drawCircle(const Offset(79, 59), 6.5, blush);

    const ink = Color(0xFF29383A);
    final expression = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (mood == PipMood.worried) {
      canvas.drawPath(
          Path()
            ..moveTo(24, 41)
            ..quadraticBezierTo(30, 38, 37, 50)
            ..moveTo(63, 50)
            ..quadraticBezierTo(70, 38, 76, 41),
          expression);
    } else {
      for (final x in [30.6, 69.4]) {
        final eye = Offset(x, 46.3);
        if (mood == PipMood.celebrate || (blink && x < 50)) {
          canvas.drawArc(Rect.fromCircle(center: eye, radius: 8.5), pi, pi,
              false, expression);
        } else {
          canvas.drawCircle(eye, 8.2, Paint()..color = ink);
          canvas.drawCircle(eye + const Offset(2.5, -2.5), 2.8,
              Paint()..color = Colors.white);
        }
      }
    }

    final mouth = switch (mood) {
      PipMood.worried => Path()
        ..moveTo(33.5, 62.2)
        ..quadraticBezierTo(50, 46, 66.5, 62.2),
      PipMood.celebrate => Path()
        ..moveTo(31.5, 67.5)
        ..quadraticBezierTo(50, 91, 68.5, 67.5),
      PipMood.happy => Path()
        ..moveTo(33.5, 72.8)
        ..quadraticBezierTo(50, 88, 66.5, 72.8),
    };
    canvas.drawPath(mouth, expression);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PipPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.blink != blink;
}

/// Lớp hoa giấy tung khi check-in thành công.
class ConfettiOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const ConfettiOverlay({super.key, required this.onDone});

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    final random = Random();
    _pieces = List.generate(40, (_) {
      return _ConfettiPiece(
        x: random.nextDouble(),
        delay: random.nextDouble() * 0.3,
        speed: 0.7 + random.nextDouble() * 0.6,
        color: [
          const Color(0xFFFFD93D),
          const Color(0xFF2BB3A3),
          const Color(0xFFFF6B9D),
          const Color(0xFF6BCBFF),
          const Color(0xFF95E77E),
        ][random.nextInt(5)],
        size: 6 + random.nextDouble() * 8,
        round: random.nextBool(),
      );
    });
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _ConfettiPainter(_pieces, _controller.value),
          );
        },
      ),
    );
  }
}

class _ConfettiPiece {
  final double x;
  final double delay;
  final double speed;
  final Color color;
  final double size;
  final bool round;
  _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.color,
    required this.size,
    required this.round,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;
  _ConfettiPainter(this.pieces, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final y = -20 + t * p.speed * (size.height + 60);
      final x = p.x * size.width + sin(t * 6 + p.x * 10) * 20;
      final paint = Paint()..color = p.color.withOpacity(1 - t * 0.4);
      if (p.round) {
        canvas.drawCircle(Offset(x, y), p.size / 2, paint);
      } else {
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset(x, y), width: p.size, height: p.size * 0.6),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
