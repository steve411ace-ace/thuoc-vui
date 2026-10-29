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

class _PipWidgetState extends State<PipWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final bounce = widget.mood == PipMood.celebrate
            ? sin(_controller.value * pi * 2) * 8
            : sin(_controller.value * pi) * 4;
        return Transform.translate(
          offset: Offset(0, -bounce.abs()),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _PipPainter(widget.mood),
          ),
        );
      },
    );
  }
}

class _PipPainter extends CustomPainter {
  final PipMood mood;
  _PipPainter(this.mood);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Bóng đổ
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.12);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, center.dy + radius * 0.92), width: radius * 1.1, height: radius * 0.22),
      shadowPaint,
    );

    // Thân viên thuốc: nửa trắng, nửa vàng (kiểu viên nang)
    final bodyPaint = Paint()..color = const Color(0xFFFFD93D);
    canvas.drawCircle(center, radius, bodyPaint);
    final whitePaint = Paint()..color = Colors.white;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(center.dx - radius, center.dy - radius, radius, radius * 2));
    canvas.drawCircle(center, radius, whitePaint);
    canvas.restore();
    // Vạch giữa viên nang
    final linePaint = Paint()
      ..color = const Color(0xFFE8A838)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), linePaint);

    // Mắt
    final eyePaint = Paint()..color = const Color(0xFF333333);
    final eyeY = center.dy - radius * 0.12;
    final eyeDx = radius * 0.32;
    if (mood == PipMood.worried) {
      // Mắt lo lắng: hai vạch chéo nhẹ
      final p = Paint()
        ..color = const Color(0xFF333333)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(center.dx - eyeDx - 8, eyeY - 6), Offset(center.dx - eyeDx + 8, eyeY + 6), p);
      canvas.drawLine(Offset(center.dx + eyeDx - 8, eyeY + 6), Offset(center.dx + eyeDx + 8, eyeY - 6), p);
    } else {
      canvas.drawCircle(Offset(center.dx - eyeDx, eyeY), radius * 0.11, eyePaint);
      canvas.drawCircle(Offset(center.dx + eyeDx, eyeY), radius * 0.11, eyePaint);
      final glint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(center.dx - eyeDx + 3, eyeY - 3), radius * 0.04, glint);
      canvas.drawCircle(Offset(center.dx + eyeDx + 3, eyeY - 3), radius * 0.04, glint);
    }

    // Miệng
    final mouthPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mouthRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + radius * 0.32),
      width: radius * 0.7,
      height: radius * 0.45,
    );
    if (mood == PipMood.worried) {
      // Miệng mếu: cung ngược
      canvas.drawArc(mouthRect, pi * 1.15, pi * 0.7, false, mouthPaint);
    } else if (mood == PipMood.celebrate) {
      // Miệng cười to
      canvas.drawArc(mouthRect, 0, pi, false, mouthPaint);
    } else {
      canvas.drawArc(mouthRect, 0.15 * pi, 0.7 * pi, false, mouthPaint);
    }

    // Má hồng
    final cheek = Paint()..color = const Color(0xFFFF9AA2).withOpacity(0.7);
    canvas.drawCircle(Offset(center.dx - radius * 0.55, center.dy + radius * 0.28), radius * 0.12, cheek);
    canvas.drawCircle(Offset(center.dx + radius * 0.55, center.dy + radius * 0.28), radius * 0.12, cheek);
  }

  @override
  bool shouldRepaint(covariant _PipPainter oldDelegate) => oldDelegate.mood != mood;
}

/// Lớp hoa giấy tung khi check-in thành công.
class ConfettiOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const ConfettiOverlay({super.key, required this.onDone});

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay> with SingleTickerProviderStateMixin {
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
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
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: p.size, height: p.size * 0.6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}
