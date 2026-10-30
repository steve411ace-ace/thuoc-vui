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
        final wave = sin(_bounce.value * pi * 2) * 7;
        final blink = widget.mood == PipMood.happy && _blink.value > 0.88;
        return Transform.translate(
          offset: Offset(0, -bounce.abs()),
          child: Transform.rotate(
            angle: tilt,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _PipPainter(widget.mood, blink: blink, wave: wave),
            ),
          ),
        );
      },
    );
  }
}

// Pip sau 18:56 30/10 (An chốt): bỏ tay chân, chỉ còn thân viên nang
// dọc trắng/vàng với khuôn mặt lớn, cân đối giữa khung; vẫn nảy,
// nghiêng nhẹ và nháy mắt định kỳ (chỉ ở tâm trạng vui).
class _PipPainter extends CustomPainter {
  final PipMood mood;
  final bool blink;
  final double wave;
  _PipPainter(this.mood, {this.blink = false, this.wave = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = size.width / 2;
    final capW = s * 0.78;
    final capH = s * 0.88;
    final capLeft = cx - capW / 2;
    final capTop = s * 0.06;
    final capRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(capLeft, capTop, capW, capH),
      Radius.circular(capW / 2),
    );
    final dark = const Color(0xFF332222);
    final outline = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Thân viên nang: vàng toàn bộ, trắng nửa trái.
    canvas.save();
    canvas.clipRRect(capRect);
    canvas.drawRRect(capRect, Paint()..color = const Color(0xFFFFD93D));
    canvas.drawRect(Rect.fromLTWH(capLeft, capTop, capW / 2, capH), Paint()..color = Colors.white);
    // Vệt bóng trên nửa vàng
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + capW * 0.22, capTop + capH * 0.18), width: capW * 0.18, height: capH * 0.28),
      Paint()..color = Colors.white.withOpacity(0.35),
    );
    canvas.restore();
    canvas.drawRRect(capRect, outline);

    // Mắt
    final eyeY = capTop + capH * 0.38;
    final eyeDx = capW * 0.22;
    final eyeR = s * 0.085;
    final eyePaint = Paint()..color = const Color(0xFF333333);
    final eyeRectL = Rect.fromCenter(center: Offset(cx - eyeDx, eyeY), width: eyeR * 2, height: eyeR * 2);
    final eyeRectR = Rect.fromCenter(center: Offset(cx + eyeDx, eyeY), width: eyeR * 2, height: eyeR * 2);
    final arcPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (mood == PipMood.worried) {
      final p = Paint()
        ..color = const Color(0xFF333333)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx - eyeDx - 8, eyeY - 6), Offset(cx - eyeDx + 8, eyeY + 6), p);
      canvas.drawLine(Offset(cx + eyeDx - 8, eyeY + 6), Offset(cx + eyeDx + 8, eyeY - 6), p);
    } else if (mood == PipMood.celebrate) {
      canvas.drawArc(eyeRectL, pi, pi, false, arcPaint);
      canvas.drawArc(eyeRectR, pi, pi, false, arcPaint);
    } else if (blink) {
      // Nháy một mắt (mẫu B): mắt trái thành vạch cong, mắt phải vẫn mở.
      canvas.drawArc(eyeRectL, pi, pi, false, arcPaint);
      canvas.drawCircle(Offset(cx + eyeDx, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(cx + eyeDx + 3, eyeY - 3), eyeR * 0.35, Paint()..color = Colors.white);
    } else {
      canvas.drawCircle(Offset(cx - eyeDx, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(cx + eyeDx, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(cx - eyeDx + 3, eyeY - 3), eyeR * 0.35, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(cx + eyeDx + 3, eyeY - 3), eyeR * 0.35, Paint()..color = Colors.white);
    }

    // Miệng
    final mouthPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mouthRect = Rect.fromCenter(
      center: Offset(cx, capTop + capH * 0.58),
      width: capW * 0.42,
      height: capH * 0.22,
    );
    if (mood == PipMood.worried) {
      canvas.drawArc(mouthRect, pi * 1.15, pi * 0.7, false, mouthPaint);
    } else if (mood == PipMood.celebrate) {
      canvas.drawArc(mouthRect, 0, pi, false, mouthPaint);
    } else {
      canvas.drawArc(mouthRect, 0.15 * pi, 0.7 * pi, false, mouthPaint);
    }

    // Má hồng
    final cheek = Paint()..color = const Color(0xFFFF9AA2).withOpacity(0.7);
    canvas.drawCircle(Offset(cx - capW * 0.33, capTop + capH * 0.50), s * 0.065, cheek);
    canvas.drawCircle(Offset(cx + capW * 0.33, capTop + capH * 0.50), s * 0.065, cheek);
  }

  @override
  bool shouldRepaint(covariant _PipPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.blink != blink || oldDelegate.wave != wave;
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
