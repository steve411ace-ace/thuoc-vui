import 'package:flutter/material.dart';

enum HomePalette {
  light('Sáng', 0xFF0F766E, 0xFFF4F6F8),
  ocean('Ocean', 0xFF175A8C, 0xFFEDF5FB),
  warm('Warm', 0xFF9A492B, 0xFFFDF2EC),
  forest('Forest', 0xFF356143, 0xFFF0F5EE),
  mint('Mint', 0xFF246A57, 0xFFEAF8F1),
  cherry('Cherry', 0xFF9C4163, 0xFFFDF0F5),
  sand('Sand', 0xFF805916, 0xFFFBF5E5),
  white('White', 0xFFFFFFFF, 0xFFF4F6F8),
  black('Black', 0xFF151515, 0xFFF4F6F8),
  custom('Custom', 0xFF0F766E, 0xFFF4F6F8);

  const HomePalette(this.label, this.primary, this.background);
  final String label;
  final int primary;
  final int background;

  static const defaultCustomColor = Color(0xFF0F766E);

  static HomePalette fromName(Object? name) => values.firstWhere(
        (palette) => palette.name == name,
        orElse: () => light,
      );

  Color accent(Color customColor) =>
      this == custom ? customColor : Color(primary);

  ThemeData themeWithCustomColor(Color customColor) {
    final accent = this.accent(customColor);
    final onPrimary =
        (this == white || this == custom) && accent.computeLuminance() > 0.179
            ? Colors.black
            : Colors.white;
    final scheme = ColorScheme.fromSeed(seedColor: accent).copyWith(
      primary: accent,
      onPrimary: onPrimary,
      surface: Colors.white,
      onSurface: const Color(0xFF1A2B2E),
      onSurfaceVariant: const Color(0xFF47575B),
    );
    final theme = ThemeData(
      colorScheme: scheme,
      fontFamily: 'Be Vietnam Pro',
      useMaterial3: true,
      scaffoldBackgroundColor: Color(background),
      appBarTheme: AppBarTheme(
        backgroundColor: accent,
        foregroundColor: onPrimary,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      textButtonTheme: scheme.surfaceAccent == accent
          ? null
          : TextButtonThemeData(
              style:
                  TextButton.styleFrom(foregroundColor: scheme.surfaceAccent),
            ),
      outlinedButtonTheme: scheme.surfaceAccent == accent
          ? null
          : OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.surfaceAccent),
            ),
      progressIndicatorTheme: scheme.surfaceAccent == accent
          ? null
          : ProgressIndicatorThemeData(color: scheme.surfaceAccent),
      sliderTheme: scheme.surfaceAccent == accent
          ? null
          : SliderThemeData(
              activeTrackColor: scheme.surfaceAccent,
              thumbColor: scheme.surfaceAccent,
            ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: 'Be Vietnam Pro',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontFamily: 'Be Vietnam Pro',
          fontSize: 12.5,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: scheme.surfaceAccent,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onPrimary,
          side: accent.computeLuminance() > 0.8
              ? BorderSide(color: scheme.outline)
              : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.surfaceAccent
                : null),
      ),
    );
    return theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: const Color(0x2410282C),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

extension HomeSurfaceAccent on ColorScheme {
  Color get surfaceAccent => onPrimary == Colors.white ? primary : onPrimary;
}

Color? doseStatusColor(String? status) => switch (status) {
      'taken' => const Color(0xFF2E7D32),
      'late' => const Color(0xFFE5A000),
      'skipped' => const Color(0xFF757575),
      _ => null,
    };

class HomeSectionLabel extends StatelessWidget {
  const HomeSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
        ),
      );
}

class HomeAppBarTitle extends StatelessWidget {
  const HomeAppBarTitle(this.title, this.subtitle, {super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class HomeTileIcon extends StatelessWidget {
  const HomeTileIcon(this.icon, {super.key}) : emoji = null;
  const HomeTileIcon.emoji(this.emoji, {super.key}) : icon = null;

  final IconData? icon;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.surfaceAccent;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: emoji == null
          ? Icon(icon, color: accent)
          : Text(emoji!, style: const TextStyle(fontSize: 22)),
    );
  }
}
