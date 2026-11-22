import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'add_medicine.dart';
import 'history.dart';
import 'home_color_picker.dart';
import 'home_style.dart';
import 'models.dart';
import 'pip.dart';
import 'purchases.dart';
import 'store.dart';
import 'widget_service.dart';

const _appVersion = '1.2.47';
const _appBuild = '50';

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
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final settings = store.settings;
        return MaterialApp(
          title: 'Thuốc Vui',
          debugShowCheckedModeBanner: false,
          theme: settings.palette.themeWithCustomColor(settings.customColor),
          darkTheme: settings.palette.darkThemeWithCustomColor(
            settings.customColor,
          ),
          themeMode: settings.appThemeMode,
          home: HomeScreen(store: store),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ThuocStore store;
  const HomeScreen({super.key, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Mở lại app sau khi bấm widget: nạp lại log để không ghi đè
      // check-in từ widget bằng bản cũ trong bộ nhớ.
      widget.store.reload();
    }
  }

  List<String> get _greetings {
    final hour = DateTime.now().hour;
    if (hour < 11) {
      return [
        'Chào buổi sáng! Uống thuốc rồi mới khỏe cả ngày nè!',
        'Sáng rồi! Pip nhắc bạn uống thuốc buổi sáng nhé!',
        'Buổi sáng tràn đầy năng lượng, uống thuốc đúng giờ nhé! ☀️',
      ];
    }
    if (hour < 14) {
      return [
        'Giờ uống thuốc trưa rồi, đừng quên nhé!',
        'Trưa rồi, uống thuốc xong nghỉ ngơi nhé!',
        'Trưa nay Pip nhắc nhẹ: uống thuốc rồi nghỉ trưa thôi!'
      ];
    }
    if (hour < 18) {
      return [
        'Chiều rồi! Còn mấy lần uống nữa là xong hôm nay!',
        'Pip đây! Nhớ uống thuốc chiều nhé!',
        'Chiều rồi, Pip cổ vũ bạn nốt mấy lần nữa là xong!'
      ];
    }
    return [
      'Uống thuốc tối xong là yên tâm đi ngủ ngon!',
      'Tối rồi, uống thuốc xong là hoàn thành ngày hôm nay!',
      'Tối nay uống thuốc xong là ngủ ngon nhé! 🌙',
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
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final slots = store.slotsForDay(today);
    final taken = slots
        .where(
            (s) => store.statusOf(s) == 'taken' || store.statusOf(s) == 'late')
        .length;
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
    final skippedCount =
        slots.where((s) => store.statusOf(s) == 'skipped').length;
    final allOnTime = slots.isNotEmpty && onTime == slots.length;
    final streak = store.onTimeStreak();
    DoseSlot? nextSlot;
    for (final s in slots) {
      if (store.statusOf(s) == null) {
        nextSlot = s;
        break;
      }
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
      pipMessage =
          'Hôm nay uống đủ hết rồi, có $lateCount lần trễ, lần sau cố đúng giờ nhé!';
    } else if (overdue) {
      pipMood = PipMood.worried;
      pipMessage = 'Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?';
    } else if (skippedCount > 0) {
      pipMood = PipMood.worried;
      pipMessage = 'Hôm nay bạn bỏ qua $skippedCount lần, mai cố nhé?';
    } else if (nextSlot != null && slots.length - taken == 1) {
      // Còn đúng 1 lần: Pip cổ vũ nốt lần cuối, thay vì chỉ chào theo giờ.
      pipMood = PipMood.happy;
      pipMessage =
          'Sắp xong rồi, cố nốt lần này nhé! 💪\nTiếp theo: ${nextSlot.medicine.formEmoji} ${nextSlot.medicine.name} lúc ${nextSlot.time}';
    } else if (nextSlot != null) {
      pipMood = PipMood.happy;
      pipMessage =
          '$_greeting\nTiếp theo: ${nextSlot.medicine.formEmoji} ${nextSlot.medicine.name} lúc ${nextSlot.time}';
    } else {
      pipMood = PipMood.happy;
      pipMessage = _greeting;
    }
    // Nhắc mua thuốc (nếu có): thêm vào cuối câu Pip để người dùng thấy
    // ngay trên trang Hôm nay, kể cả khi hôm nay đã uống đủ.
    final buyPrompt = store.todayBuyPrompt();
    final String finalPipMessage =
        buyPrompt == null ? pipMessage : '$pipMessage\n🛒 $buyPrompt';

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          children: [
            Card(
                child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.surface,
                          scheme.brightness == Brightness.light &&
                                  scheme.primary ==
                                      HomePalette.defaultCustomColor
                              ? const Color(0xFFF0F9F5)
                              : Color.alphaBlend(
                                  scheme.surfaceAccent.withAlpha(20),
                                  scheme.surface),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        PipWidget(
                          size: 54,
                          mood: pipMood,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                        begin: const Offset(0, 0.1),
                                        end: Offset.zero)
                                    .animate(anim),
                                child: child,
                              ),
                            ),
                            child: RichText(
                              key: ValueKey(finalPipMessage),
                              text: TextSpan(
                                style: TextStyle(
                                  fontFamily: 'Be Vietnam Pro',
                                  fontSize: 13,
                                  height: 1.55,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                                children: [
                                  for (int i = 0;
                                      i < finalPipMessage.split('\n').length;
                                      i++) ...[
                                    if (i > 0) const TextSpan(text: '\n'),
                                    TextSpan(
                                      text: finalPipMessage.split('\n')[i],
                                      style: finalPipMessage
                                              .split('\n')[i]
                                              .startsWith('Tiếp theo:')
                                          ? TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: scheme.surfaceAccent,
                                            )
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ))),
            const SizedBox(height: 8),
            if (slots.isEmpty) ...[
              const Card(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Chưa có thuốc nào cho hôm nay.',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      'Bấm nút bên dưới để thêm thuốc đầu tiên, Pip sẽ nhắc bạn đúng giờ.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )),
            ] else ...[
              Card(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hôm nay: đã uống $taken/${slots.length} lần • đúng giờ $onTime lần',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: slots.isEmpty ? 0 : taken / slots.length,
                        minHeight: 8,
                        backgroundColor: scheme.surfaceAccent.withAlpha(26),
                        color: scheme.surfaceAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        'Chuỗi ngày liên tục: ${store.currentStreak()} ngày 🔥'),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              _badgesSection(store),
              const SizedBox(height: 20),
              const HomeSectionLabel('Lịch uống hôm nay'),
              ...slots.map((slot) => _slotCard(slot)),
            ],
            const SizedBox(height: 24),
            if (store.medicines.isNotEmpty) ...[
              const HomeSectionLabel('Thuốc của tôi (bấm để sửa)'),
              ...store.medicines.map((med) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    leading: HomeTileIcon.emoji(med.formEmoji),
                    title: Text('${med.name} — ${med.dose}'),
                    subtitle:
                        Text('${med.times.join(', ')} • ${med.mealLabel}'),
                    trailing: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: Color(med.color), shape: BoxShape.circle)),
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = store.statusOf(slot);
    // 1.2.32: hết thuốc (còn 0 viên) thì không cho bấm Đã uống / Nhắc lại
    // sau nữa — không còn viên nào để uống; chỉ còn Bỏ qua và Đã mua hộp mới.
    // remainingPills == null nghĩa là thuốc không theo dõi số viên thì
    // không khóa (?? 1).
    final outOfStock = (store.remainingPills(slot.medicine) ?? 1) <= 0;
    final now = DateTime.now();
    final isOverdue = status == null && slot.dateTime.isBefore(now);
    final log = store.logs[slot.key];

    final stripe = doseStatusColor(isOverdue ? 'late' : status) ??
        theme.colorScheme.surfaceAccent;
    String statusText;
    if (status == 'taken') {
      final at =
          log != null && log.at.isNotEmpty ? DateTime.tryParse(log.at) : null;
      statusText = at == null
          ? 'Đã uống đúng giờ'
          : 'Đã uống đúng giờ lúc ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    } else if (status == 'late') {
      final at =
          log != null && log.at.isNotEmpty ? DateTime.tryParse(log.at) : null;
      final lateMin = at?.difference(slot.dateTime).inMinutes ?? 0;
      statusText = at == null
          ? 'Đã uống trễ'
          : 'Đã uống trễ lúc ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}${lateMin > 0 ? ' (trễ $lateMin phút)' : ''}';
    } else if (status == 'skipped') {
      statusText =
          'Đã bỏ qua${log != null && log.reason.isNotEmpty ? ' (${log.reason})' : ''}';
    } else if (isOverdue) {
      statusText = 'Quá giờ';
    } else {
      statusText = 'Sắp tới lúc ${slot.time}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: stripe, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeTileIcon.emoji(slot.medicine.formEmoji),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${slot.medicine.name} — ${slot.medicine.dose}',
                        style: theme.listTileTheme.titleTextStyle,
                      ),
                      Text(
                        'Lúc ${slot.time} • ${slot.medicine.mealLabel}'
                        '${slot.medicine.note.isNotEmpty ? ' • ${slot.medicine.note}' : ''}',
                        style: theme.listTileTheme.subtitleTextStyle,
                      ),
                      // Trạng thái nằm trong cột Expanded, không nằm ngoài Row:
                      // trước đây Text trạng thái dài (ví dụ "Đã uống trễ lúc
                      // 20:11 (trễ 671 phút)") chiếm hết chiều ngang, ép cột
                      // tên thuốc còn rộng ~1 ký tự nên chữ xếp dọc từng ký tự.
                      const SizedBox(height: 4),
                      Text(statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: doseStatusInk(
                                theme.colorScheme, isOverdue ? 'late' : status),
                          )),
                      if (store.remainingPills(slot.medicine) != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Còn ${store.remainingPills(slot.medicine)} viên'
                          '${store.daysSupply(slot.medicine) != null ? ' (đủ ${store.daysSupply(slot.medicine)} ngày)' : ''}',
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (store.remainingPills(slot.medicine) != null &&
                (store.remainingPills(slot.medicine)! <= 0 ||
                    (store.daysSupply(slot.medicine) ?? 999) <= 3)) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: const Text('Đã mua hộp mới'),
                  onPressed: () async {
                    final over = await store.buyNewBox(slot.medicine);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(over > 0
                            ? 'Đã tính lại từ hôm nay, đã trừ $over viên uống trước khi mua.'
                            : 'Đã tính lại từ hôm nay, viên bắt đầu = 1.'),
                      ),
                    );
                    final recordPurchase = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Ghi lần mua này không?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Để sau'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Ghi lần mua'),
                          ),
                        ],
                      ),
                    );
                    if (recordPurchase == true && mounted) {
                      await showPurchaseForm(context, store,
                          medicineId: slot.medicine.id);
                    }
                  },
                ),
              ),
            ],
            if (status == 'taken' || status == 'late') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Hoàn tác'),
                  style: OutlinedButton.styleFrom(foregroundColor: muted),
                  onPressed: () async {
                    await store.undoTaken(slot);
                    if (!mounted) return;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Đã hoàn tác, lần này quay lại chưa uống.')),
                    );
                  },
                ),
              ),
            ],
            if (status == null) ...[
              const SizedBox(height: 12),
              if (outOfStock) ...[
                const Text('Hết thuốc rồi, mua hộp mới trước nhé!'),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: outOfStock
                          ? null
                          : () async {
                              final beforeBadges = store.earnedBadgeIds();
                              final result = await store.markTaken(slot);
                              if (!mounted) return;
                              if (result == 'late') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Đã ghi uống trễ, lần sau cố đúng giờ nhé! ⏰')),
                                );
                              } else {
                                setState(() => _showConfetti = true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Giỏi quá! Bạn uống đúng giờ rồi! 🌟')),
                                );
                              }
                              final newBadges = store
                                  .earnedBadgeIds()
                                  .difference(beforeBadges);
                              if (newBadges.isNotEmpty && mounted) {
                                final badge = allBadges
                                    .firstWhere((b) => b.id == newBadges.first);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Mở khóa danh hiệu mới: ${badge.emoji} ${badge.title}!')),
                                );
                              }
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Đã uống', softWrap: false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: outOfStock
                          ? null
                          : () async {
                              await store.scheduleSnooze(slot.key);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Pip sẽ nhắc lại sau 10 phút nhé!')),
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Nhắc lại sau', softWrap: false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _askSkip(slot),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: muted,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Bỏ qua', softWrap: false),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badgesSection(ThuocStore store) {
    final scheme = Theme.of(context).colorScheme;
    final earned = store.earnedBadgeIds();
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Danh hiệu đúng giờ',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              'Chuỗi đúng giờ: ${store.onTimeStreak()} ngày • Tổng lần đúng giờ: ${store.totalOnTime()}',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allBadges.map((b) {
              final got = earned.contains(b.id);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      got ? scheme.surfaceAccent.withAlpha(26) : scheme.surface,
                  border: Border.all(color: scheme.surfaceAccent.withAlpha(55)),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  got ? '${b.emoji} ${b.title}' : '🔒 ${b.title}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: got ? FontWeight.bold : FontWeight.normal),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ));
  }

  Widget _settingsTab() {
    final store = widget.store;
    final settings = store.settings;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    const appModes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];

    Future<void> pickQuiet(bool isStart) async {
      final parts =
          (isStart ? settings.quietStart : settings.quietEnd).split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      );
      if (picked == null) return;
      final value =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      final next = settings.copyWith(
        quietStart: isStart ? value : settings.quietStart,
        quietEnd: isStart ? settings.quietEnd : value,
      );
      await store.updateSettings(next);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      children: [
        const HomeSectionLabel('Giao diện'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chế độ'),
                const SizedBox(height: 6),
                _ThemeModeControl(
                  labels: const ['Sáng', 'Tối', 'Theo điện thoại'],
                  systemIndex: 2,
                  selectedIndex: appModes.indexOf(settings.appThemeMode),
                  onSelected: (index) => store.updateAppTheme(appModes[index]),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 270 ? 4 : 5;
                    return Wrap(
                      runSpacing: 6,
                      children: [
                        for (final palette in HomePalette.values)
                          SizedBox(
                            width: constraints.maxWidth / columns,
                            child: HomePaletteSwatch(
                              palette: palette,
                              color: palette.accent(settings.customColor),
                              selected: settings.palette == palette,
                              onTap: () async {
                                if (palette == HomePalette.custom) {
                                  final color = await showDialog<Color>(
                                    context: context,
                                    builder: (_) => HomeColorPicker(
                                      initialColor: store.settings.customColor,
                                    ),
                                  );
                                  if (color == null) return;
                                  await store.updateAppearance(palette,
                                      customColor: color);
                                } else {
                                  await store.updateAppearance(palette);
                                }
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const HomeSectionLabel('Độ mờ widget'),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Nền widget trong suốt dần khi kéo xuống, chữ và nút vẫn giữ nguyên. 100% là đặc như hiện tại, 0% là nền biến mất hoàn toàn.',
                  style: TextStyle(color: muted)),
              Row(
                children: [
                  const Text('Mờ hơn'),
                  Expanded(
                    child: Slider(
                      value: (settings.widgetOpacity / 100).clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${settings.widgetOpacity}%',
                      onChanged: (v) async {
                        await store.updateSettings(settings.copyWith(
                            widgetOpacity: (v * 100).round()));
                      },
                    ),
                  ),
                  Text('${settings.widgetOpacity}%',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Giao diện widget'),
              const SizedBox(height: 6),
              _ThemeModeControl(
                labels: const ['Theo điện thoại', 'Sáng', 'Tối'],
                systemIndex: 0,
                selectedIndex: settings.widgetThemeMode.index,
                onSelected: (index) =>
                    store.updateWidgetTheme(WidgetThemeMode.values[index]),
              ),
            ],
          ),
        )),
        const SizedBox(height: 16),
        const HomeSectionLabel('Nhắc uống thuốc'),
        Card(
            child: Column(children: [
          SwitchListTile(
            title: const Text('Âm thanh nhắc'),
            value: settings.sound,
            onChanged: (v) async {
              await store.updateSettings(settings.copyWith(sound: v));
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('Rung khi nhắc'),
            value: settings.vibration,
            onChanged: (v) async {
              await store.updateSettings(settings.copyWith(vibration: v));
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                _SettingsField(
                  label: 'Giờ yên lặng bắt đầu',
                  value: settings.quietStart,
                  onTap: () => pickQuiet(true),
                ),
                const SizedBox(height: 11),
                _SettingsField(
                  label: 'Giờ yên lặng kết thúc',
                  value: settings.quietEnd,
                  onTap: () => pickQuiet(false),
                ),
              ],
            ),
          ),
        ])),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Trong giờ yên lặng, app không lên lịch nhắc mới. Các lần uống vẫn hiện trên lịch hôm nay.',
            style: TextStyle(color: muted),
          ),
        ),
        const SizedBox(height: 16),
        const HomeSectionLabel('Thông báo'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Lịch nhắc dùng báo thức hệ thống. Nếu đã từ chối quyền vĩnh viễn, bật thủ công tại Cài đặt máy > Ứng dụng > Thuốc Vui > Thông báo.',
                    style: TextStyle(color: muted),
                  ),
                ),
                // Nút thông báo xếp dọc full-width, không chia đôi nữa: chia đôi
                // làm chữ dài bị wrap 2 dòng, trông xấu và khó bấm.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Xin quyền thông báo'),
                    onPressed: () async {
                      final granted =
                          await store.requestNotificationPermission();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(granted
                              ? 'Đã có quyền thông báo, lịch nhắc đã lên lại!'
                              : 'Chưa có quyền thông báo. Anh bật tay: Cài đặt máy > Ứng dụng > Thuốc Vui > Thông báo.'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.alarm_outlined),
                    label: const Text('Cho phép báo thức chính xác'),
                    onPressed: () async {
                      final canExact = await store.canScheduleExact();
                      if (canExact) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Máy đã cho phép báo thức chính xác rồi, nhắc sẽ đúng giờ.')),
                        );
                        return;
                      }
                      await store.requestExactAlarmPermission();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Đã mở màn hình Báo thức & nhắc nhở. Bật "Cho phép đặt báo thức và nhắc nhở" cho Thuốc Vui nhé!')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.battery_charging_full_outlined),
                    label: const Text('Tắt tối ưu pin cho Thuốc Vui'),
                    onPressed: () async {
                      final opened =
                          await store.requestIgnoreBatteryOptimizations();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(opened
                                ? 'Đã mở màn hình miễn tối ưu pin. Bấm "Cho phép" để Thuốc Vui không bị máy cho ngủ, lịch theo giờ mới chạy được.'
                                : 'Không mở được màn hình pin. Vào Cài đặt máy > Ứng dụng > Thuốc Vui > Pin > Không giới hạn nhé!')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _SettingsField(
                label: 'Báo lại sau mỗi',
                value: '${settings.remindIntervalMinutes} phút',
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
                              child: Text('$m phút',
                                  style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                      ],
                    ),
                  );
                  if (picked != null) {
                    await store.updateSettings(
                        settings.copyWith(remindIntervalMinutes: picked));
                  }
                },
              ),
              const SizedBox(height: 11),
              _SettingsField(
                label: 'Số lần báo lại nếu chưa uống',
                value: settings.remindTimes == 0
                    ? 'Tắt'
                    : '${settings.remindTimes} lần',
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
                              child: Text(n == 0 ? 'Tắt' : '$n lần',
                                  style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                      ],
                    ),
                  );
                  if (picked != null) {
                    await store
                        .updateSettings(settings.copyWith(remindTimes: picked));
                  }
                },
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Sau lần nhắc chính, app tự động báo lại nếu chưa bấm đã uống. Bấm đã uống trong app, trên widget hoặc thông báo sẽ dừng báo lại cho lần đó.',
            style: TextStyle(color: muted),
          ),
        ),
        const Divider(height: 32),
        Text(
          'Lưu ý: app chỉ nhắc giờ uống và ghi nhận đã uống, không thay thế chỉ định của bác sĩ. Khởi động lại điện thoại xong, mở app một lần để lịch nhắc hoạt động lại.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        Center(
            child: Text('Thuốc Vui • Phiên bản $_appVersion+$_appBuild',
                style: TextStyle(color: muted))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, child) {
        if (!widget.store.loaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 82,
            titleSpacing: 22,
            flexibleSpace: const HomeHeaderBackground(),
            actions: [
              Builder(builder: (context) {
                final ink = Theme.of(context).colorScheme.onPrimary;
                return Container(
                  margin: const EdgeInsets.only(right: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: ink.withAlpha(16),
                    border: Border.all(color: ink.withAlpha(40)),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(_appVersion,
                      style: TextStyle(fontSize: 11, color: ink)),
                );
              }),
            ],
            title: HomeAppBarTitle(
                'Thuốc Vui', ['Hôm nay', 'Lịch sử', 'Cài đặt'][_tab],
                icon: Icons.medication_outlined),
            centerTitle: false,
          ),
          body: _tab == 0
              ? _homeTab()
              : _tab == 1
                  ? HistoryScreen(store: widget.store)
                  : Theme(
                      data: Theme.of(context).copyWith(
                        cardTheme: Theme.of(context).cardTheme.copyWith(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              shadowColor: const Color(0x16173E2C),
                            ),
                      ),
                      child: _settingsTab(),
                    ),
          floatingActionButton: _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _openAdd(),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm thuốc',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : null,
          bottomNavigationBar: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: NavigationBar(
              height: 68,
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor:
                  Theme.of(context).colorScheme.surfaceAccent.withAlpha(26),
              indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)),
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                // Chuyển về tab Hôm nay sau khi bấm nút thông báo / widget:
                // app đang mở sẵn không có sự kiện resumed, nên phải nạp lại
                // ở đây thì tiến độ mới hiện, kể cả khi Kotlin vừa ghi log.
                if (i == 0) widget.store.reload();
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.today_outlined), label: 'Hôm nay'),
                NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    label: 'Lịch sử'),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined), label: 'Cài đặt'),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color _settingsTrackColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? const Color(0xFF253D36)
        : const Color(0xFFF0F4F1);

class _ThemeModeControl extends StatelessWidget {
  const _ThemeModeControl({
    required this.labels,
    required this.systemIndex,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int systemIndex;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _settingsTrackColor(scheme),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              if (index > 0) const SizedBox(width: 3),
              Expanded(
                flex: index == systemIndex ? 3 : 2,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: index == selectedIndex
                        ? scheme.surfaceAccent
                        : scheme.onSurfaceVariant,
                    backgroundColor: index == selectedIndex
                        ? scheme.surface
                        : Colors.transparent,
                    elevation: index == selectedIndex ? 1 : 0,
                    shadowColor: const Color(0x20153A23),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    minimumSize: const Size(0, 42),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: index == selectedIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onPressed: () => onSelected(index),
                  child: Semantics(
                    selected: index == selectedIndex,
                    child: Text(labels[index], textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: _settingsTrackColor(scheme),
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: theme.dividerColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onTap,
            child: Row(
              children: [
                Expanded(child: Text(value)),
                Icon(Icons.keyboard_arrow_down, color: scheme.surfaceAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
