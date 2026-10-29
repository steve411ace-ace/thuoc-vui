import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'add_medicine.dart';
import 'history.dart';
import 'models.dart';
import 'pip.dart';
import 'store.dart';
import 'widget_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.registerInteractivityCallback(widgetInteractivityCallback);
  final store = ThuocStore();
  await store.init();
  runApp(ThuocVuiApp(store: store));
}

class ThuocVuiApp extends StatelessWidget {
  final ThuocStore store;
  const ThuocVuiApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thuốc Vui',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2BB3A3)),
        scaffoldBackgroundColor: const Color(0xFFFFF8E6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFD93D),
          foregroundColor: Color(0xFF333333),
        ),
      ),
      home: HomeScreen(store: store),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ThuocStore store;
  const HomeScreen({super.key, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _showConfetti = false;

  List<String> get _greetings {
    final hour = DateTime.now().hour;
    if (hour < 11) {
      return [
        'Chào buổi sáng! Uống thuốc rồi mới khỏe cả ngày nè!',
        'Sáng rồi! Pip nhắc bạn uống thuốc buổi sáng nhé!',
      ];
    }
    if (hour < 14) {
      return ['Giờ uống thuốc trưa rồi, đừng quên nhé!', 'Trưa rồi, uống thuốc xong nghỉ ngơi nhé!'];
    }
    if (hour < 18) {
      return ['Chiều rồi! Còn mấy lần uống nữa là xong hôm nay!', 'Pip đây! Nhớ uống thuốc chiều nhé!'];
    }
    return [
      'Uống thuốc tối xong là yên tâm đi ngủ ngon!',
      'Tối rồi, uống thuốc xong là hoàn thành ngày hôm nay!',
    ];
  }

  String get _greeting {
    final list = _greetings;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return list[dayOfYear % list.length];
  }

  Future<void> _openAdd([Medicine? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicineScreen(
          existing: existing,
          onSave: (med) async {
            if (existing == null) {
              await widget.store.addMedicine(med);
            } else {
              await widget.store.updateMedicine(med);
            }
            if (mounted) Navigator.pop(context);
          },
          onDelete: existing == null
              ? null
              : () async {
                  await widget.store.deleteMedicine(existing.id);
                  if (mounted) Navigator.pop(context);
                },
        ),
      ),
    );
  }

  Future<void> _askSkip(DoseSlot slot) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bỏ qua lần uống này?'),
        children: [
          for (final r in ['Quên', 'Hết thuốc', 'Khó chịu', 'Khác'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(r, style: const TextStyle(fontSize: 16)),
              ),
            ),
        ],
      ),
    );
    if (reason != null) {
      await widget.store.markSkipped(slot, reason);
    }
  }

  Widget _homeTab() {
    final store = widget.store;
    final today = DateTime.now();
    final slots = store.slotsForDay(today);
    final taken = slots.where((s) => store.statusOf(s) == 'taken' || store.statusOf(s) == 'late').length;
    final onTime = slots.where((s) => store.statusOf(s) == 'taken').length;
    final overdue = slots.any((s) =>
        store.statusOf(s) == null && s.dateTime.isBefore(DateTime.now()));
    final allDone = slots.isNotEmpty && taken == slots.length;
    // Cải tiến Pip (theo yêu cầu sau bản 1.2, gộp luôn vào bản sửa build này):
    // trước đây Pip chỉ có 3 trạng thái thô (đủ = ăn mừng, quá giờ = lo,
    // còn lại = vui + câu chào theo giờ). Nay Pip phân biệt rõ hơn:
    // đủ + đúng giờ hết, đủ nhưng có trễ, bỏ qua, quá giờ, và luôn cho biết
    // lần uống tiếp theo + chuỗi đúng giờ, để mặt và thông tin khớp với thực tế.
    final lateCount = slots.where((s) => store.statusOf(s) == 'late').length;
    final skippedCount = slots.where((s) => store.statusOf(s) == 'skipped').length;
    final allOnTime = slots.isNotEmpty && onTime == slots.length;
    final streak = store.onTimeStreak();
    DoseSlot? nextSlot;
    for (final s in slots) {
      if (store.statusOf(s) == null) { nextSlot = s; break; }
    }
    final PipMood pipMood;
    final String pipMessage;
    if (allOnTime) {
      pipMood = PipMood.celebrate;
      pipMessage = streak >= 2
          ? 'Hôm nay bạn uống đủ và đúng giờ hết rồi, tuyệt vời! Chuỗi đúng giờ: $streak ngày 🔥'
          : 'Hôm nay bạn uống đủ và đúng giờ hết rồi, tuyệt vời!';
    } else if (allDone) {
      pipMood = PipMood.happy;
      pipMessage = 'Hôm nay uống đủ hết rồi, có $lateCount lần trễ, lần sau cố đúng giờ nhé!';
    } else if (overdue) {
      pipMood = PipMood.worried;
      pipMessage = 'Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?';
    } else if (skippedCount > 0) {
      pipMood = PipMood.worried;
      pipMessage = 'Hôm nay bạn bỏ qua $skippedCount lần, mai cố nhé?';
    } else if (nextSlot != null) {
      pipMood = PipMood.happy;
      pipMessage = '$_greeting\nTiếp theo: ${nextSlot.medicine.formEmoji} ${nextSlot.medicine.name} lúc ${nextSlot.time}';
    } else {
      pipMood = PipMood.happy;
      pipMessage = _greeting;
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                PipWidget(
                  size: 96,
                  mood: pipMood,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Text(
                      pipMessage,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (slots.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  children: [
                    Text('Chưa có thuốc nào cho hôm nay.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      'Bấm nút bên dưới để thêm thuốc đầu tiên, Pip sẽ nhắc bạn đúng giờ.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hôm nay: đã uống $taken/${slots.length} lần • đúng giờ $onTime lần',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: slots.isEmpty ? 0 : taken / slots.length,
                        minHeight: 12,
                        backgroundColor: const Color(0xFFFFE9A8),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2BB3A3)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Chuỗi ngày liên tục: ${store.currentStreak()} ngày 🔥'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _badgesSection(store),
              const SizedBox(height: 20),
              const Text('Lịch uống hôm nay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...slots.map((slot) => _slotCard(slot)),
            ],
            const SizedBox(height: 24),
            if (store.medicines.isNotEmpty) ...[
              const Text('Thuốc của tôi (bấm để sửa)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...store.medicines.map((med) {
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: Text(med.formEmoji, style: const TextStyle(fontSize: 28)),
                    title: Text('${med.name} — ${med.dose}'),
                    subtitle: Text('${med.times.join(', ')} • ${med.mealLabel}'),
                    trailing: Container(width: 14, height: 14, decoration: BoxDecoration(color: Color(med.color), shape: BoxShape.circle)),
                    onTap: () => _openAdd(med),
                  ),
                );
              }),
            ],
            const SizedBox(height: 90),
          ],
        ),
        if (_showConfetti)
          ConfettiOverlay(onDone: () => setState(() => _showConfetti = false)),
      ],
    );
  }

  Widget _slotCard(DoseSlot slot) {
    final store = widget.store;
    final status = store.statusOf(slot);
    final now = DateTime.now();
    final isOverdue = status == null && slot.dateTime.isBefore(now);
    final log = store.logs[slot.key];

    Color cardColor = Colors.white;
    String statusText;
    if (status == 'taken') {
      cardColor = const Color(0xFFE3F7E8);
      final at = log != null && log.at.isNotEmpty ? DateTime.tryParse(log.at) : null;
      statusText = at == null
          ? 'Đã uống đúng giờ'
          : 'Đã uống đúng giờ lúc ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    } else if (status == 'late') {
      cardColor = const Color(0xFFFFF0D6);
      final at = log != null && log.at.isNotEmpty ? DateTime.tryParse(log.at) : null;
      final lateMin = at?.difference(slot.dateTime).inMinutes ?? 0;
      statusText = at == null
          ? 'Đã uống trễ'
          : 'Đã uống trễ lúc ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}${lateMin > 0 ? ' (trễ $lateMin phút)' : ''}';
    } else if (status == 'skipped') {
      cardColor = const Color(0xFFF1F1F1);
      statusText = 'Đã bỏ qua${log != null && log.reason.isNotEmpty ? ' (${log.reason})' : ''}';
    } else if (isOverdue) {
      cardColor = const Color(0xFFFFF0D6);
      statusText = 'Quá giờ';
    } else {
      statusText = 'Sắp tới lúc ${slot.time}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border(left: BorderSide(color: Color(slot.medicine.color), width: 6)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(slot.medicine.formEmoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slot.medicine.name} — ${slot.medicine.dose}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Lúc ${slot.time} • ${slot.medicine.mealLabel}'
                      '${slot.medicine.note.isNotEmpty ? ' • ${slot.medicine.note}' : ''}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    // Trạng thái nằm trong cột Expanded, không nằm ngoài Row:
                    // trước đây Text trạng thái dài (ví dụ "Đã uống trễ lúc
                    // 20:11 (trễ 671 phút)") chiếm hết chiều ngang, ép cột
                    // tên thuốc còn rộng ~1 ký tự nên chữ xếp dọc từng ký tự.
                    const SizedBox(height: 4),
                    Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          if (status == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final beforeBadges = store.earnedBadgeIds();
                      final result = await store.markTaken(slot);
                      if (!mounted) return;
                      if (result == 'late') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã ghi uống trễ, lần sau cố đúng giờ nhé! ⏰')),
                        );
                      } else {
                        setState(() => _showConfetti = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Giỏi quá! Bạn uống đúng giờ rồi! 🌟')),
                        );
                      }
                      final newBadges = store.earnedBadgeIds().difference(beforeBadges);
                      if (newBadges.isNotEmpty && mounted) {
                        final badge = allBadges.firstWhere((b) => b.id == newBadges.first);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Mở khóa danh hiệu mới: ${badge.emoji} ${badge.title}!')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2BB3A3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Đã uống'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await store.scheduleSnooze(slot.key);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pip sẽ nhắc lại sau 10 phút nhé!')),
                      );
                    },
                    child: const Text('Nhắc lại sau'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _askSkip(slot),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.black54),
                    child: const Text('Bỏ qua'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _badgesSection(ThuocStore store) {
    final earned = store.earnedBadgeIds();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Danh hiệu đúng giờ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Chuỗi đúng giờ: ${store.onTimeStreak()} ngày • Tổng lần đúng giờ: ${store.totalOnTime()}',
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allBadges.map((b) {
              final got = earned.contains(b.id);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: got ? const Color(0xFFFFF0D6) : const Color(0xFFF1F1F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  got ? '${b.emoji} ${b.title}' : '🔒 ${b.title}',
                  style: TextStyle(fontWeight: got ? FontWeight.bold : FontWeight.normal),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _settingsTab() {
    final store = widget.store;
    final settings = store.settings;

    Future<void> pickQuiet(bool isStart) async {
      final parts = (isStart ? settings.quietStart : settings.quietEnd).split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      );
      if (picked == null) return;
      final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      final next = settings.copyWith(
        quietStart: isStart ? value : settings.quietStart,
        quietEnd: isStart ? settings.quietEnd : value,
      );
      await store.updateSettings(next);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Cài đặt', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Âm thanh nhắc'),
          value: settings.sound,
          onChanged: (v) async {
            await store.updateSettings(settings.copyWith(sound: v));
          },
        ),
        SwitchListTile(
          title: const Text('Rung khi nhắc'),
          value: settings.vibration,
          onChanged: (v) async {
            await store.updateSettings(settings.copyWith(vibration: v));
          },
        ),
        ListTile(
          title: const Text('Giờ yên lặng bắt đầu'),
          trailing: Text(settings.quietStart, style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => pickQuiet(true),
        ),
        ListTile(
          title: const Text('Giờ yên lặng kết thúc'),
          trailing: Text(settings.quietEnd, style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => pickQuiet(false),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Trong giờ yên lặng, app không lên lịch nhắc mới. Các lần uống trong khoảng này vẫn hiện trên lịch hôm nay.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        const Divider(height: 32),
        const Text('Thông báo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nếu chưa từng thấy thông báo, bấm "Gửi thông báo thử" trước: thông báo thử sẽ tạo kênh nhắc để app xuất hiện trong Cài đặt > Thông báo của máy. Nếu máy đã từ chối quyền vĩnh viễn thì hộp xin quyền sẽ không hiện nữa, anh bật tay theo đường dẫn: Cài đặt máy > Ứng dụng > Thuốc Vui > Thông báo.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  await store.sendTestNotification();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã gửi thông báo thử. Kiểm tra thanh thông báo nhé!')),
                  );
                },
                child: const Text('Gửi thông báo thử'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final granted = await store.requestNotificationPermission();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(granted
                          ? 'Đã có quyền thông báo, lịch nhắc đã lên lại!'
                          : 'Chưa có quyền thông báo. Anh bật tay: Cài đặt máy > Ứng dụng > Thuốc Vui > Thông báo.'),
                    ),
                  );
                },
                child: const Text('Xin quyền thông báo'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final canExact = await store.canScheduleExact();
            if (canExact) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Máy đã cho phép báo thức chính xác rồi, nhắc sẽ đúng giờ.')),
              );
              return;
            }
            await store.requestExactAlarmPermission();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã mở màn hình Báo thức & nhắc nhở. Bật "Cho phép đặt báo thức và nhắc nhở" cho Thuốc Vui nhé!')),
            );
          },
          child: const Text('Cho phép báo thức chính xác'),
        ),
        ListTile(
          title: const Text('Báo lại sau mỗi'),
          trailing: Text('${settings.remindIntervalMinutes} phút',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () async {
            final picked = await showDialog<int>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Báo lại sau mỗi'),
                children: [
                  for (final m in [5, 10, 15, 30, 60])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('$m phút', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                ],
              ),
            );
            if (picked != null) {
              await store.updateSettings(settings.copyWith(remindIntervalMinutes: picked));
            }
          },
        ),
        ListTile(
          title: const Text('Số lần báo lại nếu chưa uống'),
          trailing: Text(settings.remindTimes == 0 ? 'Tắt' : '${settings.remindTimes} lần',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () async {
            final picked = await showDialog<int>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Số lần báo lại nếu chưa uống'),
                children: [
                  for (final n in [0, 1, 2, 3, 5])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(n == 0 ? 'Tắt' : '$n lần', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                ],
              ),
            );
            if (picked != null) {
              await store.updateSettings(settings.copyWith(remindTimes: picked));
            }
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Báo lại là nhắc tự động sau lần nhắc chính, chỉ khi chưa bấm đã uống. Bấm đã uống trong app sẽ hủy các lần báo lại còn lại trong ngày đó.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        const Divider(height: 32),
        const Text('Sao lưu dữ liệu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Gỡ app sẽ xóa dữ liệu trong máy. Trước khi gỡ để cài bản mới, bấm Sao lưu rồi dán chuỗi sao lưu vào Ghi chú hoặc email để giữ. Sau khi cài lại, bấm Khôi phục rồi dán chuỗi đó vào.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: store.exportBackup()));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã copy chuỗi sao lưu. Dán vào Ghi chú hoặc email để giữ lại nhé!')),
                  );
                },
                child: const Text('Sao lưu (copy)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final controller = TextEditingController();
                  final pasted = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Khôi phục dữ liệu'),
                      content: TextField(
                        controller: controller,
                        maxLines: 5,
                        decoration: const InputDecoration(hintText: 'Dán chuỗi sao lưu vào đây'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Khôi phục')),
                      ],
                    ),
                  );
                  if (pasted == null || pasted.trim().isEmpty) return;
                  final ok = await store.importBackup(pasted.trim());
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Khôi phục xong!' : 'Chuỗi sao lưu không đúng định dạng, chưa đổi gì cả.')),
                  );
                },
                child: const Text('Khôi phục (dán)'),
              ),
            ),
          ],
        ),
        const Divider(height: 32),
        const Text(
          'Lưu ý: app chỉ nhắc giờ uống và ghi lại việc đã uống, không thay thế chỉ định của bác sĩ. Sau khi khởi động lại điện thoại, mở app một lần để lịch nhắc hoạt động lại.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Xóa toàn bộ dữ liệu?'),
                content: const Text('Toàn bộ thuốc, lịch nhắc và lịch sử sẽ bị xóa khỏi máy.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa hết', style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (ok == true) await store.clearAll();
          },
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
          child: const Text('Xóa toàn bộ dữ liệu'),
        ),
        const SizedBox(height: 16),
        const Center(child: Text('Thuốc Vui • Phiên bản 1.2.4', style: TextStyle(color: Colors.black54))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, child) {
        if (!widget.store.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Thuốc Vui 💊', style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: false,
          ),
          body: _tab == 0
              ? _homeTab()
              : _tab == 1
                  ? HistoryScreen(store: widget.store)
                  : _settingsTab(),
          floatingActionButton: _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _openAdd(),
                  backgroundColor: const Color(0xFFFFD93D),
                  foregroundColor: const Color(0xFF333333),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm thuốc', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : null,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.today), label: 'Hôm nay'),
              BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Lịch sử'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Cài đặt'),
            ],
          ),
        );
      },
    );
  }
}
