import 'dart:convert';

/// Một loại thuốc người dùng cần uống.
class Medicine {
  final String id;
  final String name;
  final String dose; // ví dụ: "1 viên", "5 ml"
  final String form; // vien, nuoc, tiem, xit, khac
  final int color; // ARGB
  final List<String> times; // ["08:00", "20:00"]
  final List<int> weekdays; // 1=Thứ 2 ... 7=Chủ nhật
  final String startDate; // yyyy-MM-dd
  final String? endDate; // yyyy-MM-dd hoặc null = dài hạn
  final String mealNote; // truoc_an, sau_an, khong
  final String note;

  Medicine({
    required this.id,
    required this.name,
    required this.dose,
    required this.form,
    required this.color,
    required this.times,
    required this.weekdays,
    required this.startDate,
    this.endDate,
    required this.mealNote,
    required this.note,
  });

  String get formEmoji {
    switch (form) {
      case 'nuoc':
        return '💧';
      case 'tiem':
        return '💉';
      case 'xit':
        return '🌬️';
      case 'khac':
        return '💊';
      case 'vien':
      default:
        return '💊';
    }
  }

  String get formLabel {
    switch (form) {
      case 'nuoc':
        return 'Thuốc nước';
      case 'tiem':
        return 'Thuốc tiêm';
      case 'xit':
        return 'Thuốc xịt';
      case 'khac':
        return 'Thuốc khác';
      case 'vien':
      default:
        return 'Thuốc viên';
    }
  }

  String get mealLabel {
    switch (mealNote) {
      case 'truoc_an':
        return 'Uống trước ăn';
      case 'sau_an':
        return 'Uống sau ăn';
      default:
        return 'Không dặn trước/sau ăn';
    }
  }

  bool activeOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime.parse(startDate);
    if (d.isBefore(start)) return false;
    if (endDate != null && endDate!.isNotEmpty) {
      final end = DateTime.parse(endDate!);
      if (d.isAfter(end)) return false;
    }
    return weekdays.contains(d.weekday);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'form': form,
        'color': color,
        'times': times,
        'weekdays': weekdays,
        'startDate': startDate,
        'endDate': endDate,
        'mealNote': mealNote,
        'note': note,
      };

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'] as String,
        name: j['name'] as String,
        dose: j['dose'] as String? ?? '',
        form: j['form'] as String? ?? 'vien',
        color: j['color'] as int? ?? 0xFF2BB3A3,
        times: (j['times'] as List<dynamic>).map((e) => e.toString()).toList(),
        weekdays: (j['weekdays'] as List<dynamic>).map((e) => (e as num).toInt()).toList(),
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String?,
        mealNote: j['mealNote'] as String? ?? 'khong',
        note: j['note'] as String? ?? '',
      );
}

/// Một lần uống cụ thể trong một ngày (thuốc + giờ).
class DoseSlot {
  final Medicine medicine;
  final String time; // HH:mm
  final DateTime day;

  DoseSlot({required this.medicine, required this.time, required this.day});

  String get key {
    final d =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return '${medicine.id}|$d|$time';
  }

  DateTime get dateTime {
    final parts = time.split(':');
    return DateTime(day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
  }
}

/// Trạng thái check-in của một lần uống.
class DoseLog {
  final String status; // taken, skipped
  final String at; // ISO thời điểm check-in
  final String reason; // lý do bỏ qua (nếu có)

  DoseLog({required this.status, required this.at, this.reason = ''});

  Map<String, dynamic> toJson() => {'status': status, 'at': at, 'reason': reason};

  factory DoseLog.fromJson(Map<String, dynamic> j) => DoseLog(
        status: j['status'] as String,
        at: j['at'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
      );
}

String todayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatTimeLabel(String hhmm) => hhmm;

String formatDateVn(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Hash ổn định qua các lần chạy (không dùng String.hashCode vì có thể đổi).
int stableHash(String s) {
  var h = 5381;
  for (var i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.codeUnitAt(i)) & 0x7fffffff;
  }
  return h;
}

Map<String, dynamic> decodeJson(String raw) {
  return jsonDecode(raw) as Map<String, dynamic>;
}
