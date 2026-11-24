import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Ngôn ngữ giao diện. Mặc định Tiếng Việt, lưu trong AppSettings.language.
enum AppLang {
  vi('vi', 'Tiếng Việt'),
  en('en', 'English');

  final String code;
  final String label;
  const AppLang(this.code, this.label);

  static AppLang fromCode(Object? code) =>
      code == 'en' ? AppLang.en : AppLang.vi;
}

/// Ngôn ngữ đang dùng (đặt bởi ThuocStore khi nạp / đổi cài đặt).
class Lang {
  static AppLang current = AppLang.vi;
  static bool get isEn => current == AppLang.en;
  static String get code => current.code;
}

/// Chọn chuỗi theo ngôn ngữ hiện tại: tr('Tiếng Việt', 'English').
String tr(String vi, String en) => Lang.isEn ? en : vi;

/// Số nhiều tiếng Anh đơn giản: plural(n, 'dose', 'doses') -> 'dose'/'doses'.
String enPlural(int n, String one, String many) => n == 1 ? one : many;

const _viWeekdayFull = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];
const _enWeekdayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _viWeekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
const _enWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _enMonthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// weekday theo DateTime.weekday (1 = Thứ Hai ... 7 = Chủ Nhật).
String weekdayFull(int weekday) =>
    (Lang.isEn ? _enWeekdayFull : _viWeekdayFull)[(weekday - 1) % 7];

/// "T2".."CN" / "Mon".."Sun".
String weekdayShort(int weekday) =>
    (Lang.isEn ? _enWeekdayShort : _viWeekdayShort)[(weekday - 1) % 7];

/// "24 Thg 11" / "Nov 24".
String monthDayLabel(DateTime d) =>
    Lang.isEn ? '${_enMonthShort[d.month - 1]} ${d.day}' : '${d.day} Thg ${d.month}';

/// Ngày đầy đủ: "24/11/2026" (vi) / "11/24/2026" (en).
String formatDateLocal(DateTime d) =>
    Lang.isEn ? '${d.month}/${d.day}/${d.year}' : '${d.day}/${d.month}/${d.year}';

/// Lá cờ vẽ bằng widget (không dùng emoji cờ để khỏi phụ thuộc font).
/// Việt Nam: nền đỏ + sao vàng 5 cánh. English: cờ Anh (Union Jack).
class FlagIcon extends StatelessWidget {
  final AppLang lang;
  final double width;
  const FlagIcon({super.key, required this.lang, this.width = 30});

  @override
  Widget build(BuildContext context) {
    final height = width * 2 / 3;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: lang == AppLang.vi ? _VietnamFlagPainter() : _UkFlagPainter(),
        ),
      ),
    );
  }
}

class _VietnamFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFDA251D),
    );
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.height * 0.30;
    final inner = outer * 0.382;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFF00));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UkFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const blue = Color(0xFF012169);
    const red = Color(0xFFC8102E);
    canvas.drawRect(Offset.zero & size, Paint()..color = blue);
    final white = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = h * 0.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(w, h), white);
    canvas.drawLine(Offset(w, 0), Offset(0, h), white);
    final redThin = Paint()
      ..color = red
      ..strokeWidth = h * 0.07
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(w, h), redThin);
    canvas.drawLine(Offset(w, 0), Offset(0, h), redThin);
    final whiteCross = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.5 - h * 0.17, w, h * 0.34), whiteCross);
    canvas.drawRect(Rect.fromLTWH(w * 0.5 - h * 0.17, 0, h * 0.34, h), whiteCross);
    final redCross = Paint()..color = red;
    canvas.drawRect(Rect.fromLTWH(0, h * 0.5 - h * 0.1, w, h * 0.2), redCross);
    canvas.drawRect(Rect.fromLTWH(w * 0.5 - h * 0.1, 0, h * 0.2, h), redCross);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Lý do bỏ qua được lưu bằng tiếng Việt (dữ liệu cũ); chỉ dịch khi hiển thị.
String skipReasonLabel(String stored) {
  if (!Lang.isEn) return stored;
  return switch (stored) {
    'Quên' => 'Forgot',
    'Hết thuốc' => 'Out of stock',
    'Khó chịu' => 'Felt unwell',
    'Khác' => 'Other',
    _ => stored,
  };
}
