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

  ThemeData themeWithCustomColor(Color customColor) =>
      _theme(customColor, Brightness.light);

  ThemeData darkThemeWithCustomColor(Color customColor) =>
      _theme(customColor, Brightness.dark);

  ThemeData _theme(Color customColor, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = this.accent(customColor);
    final onPrimary = (dark || this == white || this == custom) &&
            accent.computeLuminance() > 0.179
        ? Colors.black
        : Colors.white;
    final seededScheme =
        ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    final scheme = seededScheme.copyWith(
      primary: accent,
      onPrimary: onPrimary,
      surface: dark ? const Color(0xFF1C2629) : Colors.white,
      onSurface: dark ? const Color(0xFFEDEDED) : const Color(0xFF1A2B2E),
      onSurfaceVariant:
          dark ? const Color(0xFFB8C4C2) : const Color(0xFF47575B),
    );
    final theme = ThemeData(
      colorScheme: scheme,
      fontFamily: 'Be Vietnam Pro',
      useMaterial3: true,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF12181B) : Color(background),
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
      dividerColor: dark ? const Color(0xFF344541) : const Color(0xFFE7EEEA),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.surfaceAccent.withAlpha(60)),
        selectedColor: scheme.surfaceAccent.withAlpha(28),
        showCheckmark: false,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.surfaceAccent,
          side: BorderSide(color: scheme.surfaceAccent.withAlpha(75)),
          shape: const StadiumBorder(),
        ),
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
        shape: const StadiumBorder(),
        elevation: 2,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.surfaceAccent,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      switchTheme: dark
          ? SwitchThemeData(
              trackColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) &&
                          !states.contains(WidgetState.disabled)
                      ? scheme.surfaceAccent
                      : null),
              thumbColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) &&
                          !states.contains(WidgetState.disabled)
                      ? scheme.surface
                      : null),
            )
          : null,
      textSelectionTheme: dark
          ? TextSelectionThemeData(
              cursorColor: scheme.surfaceAccent,
              selectionColor: scheme.surfaceAccent.withAlpha(102),
              selectionHandleColor: scheme.surfaceAccent,
            )
          : null,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        focusedBorder: dark
            ? OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: scheme.surfaceAccent, width: 2),
              )
            : null,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onPrimary,
          shape: const StadiumBorder(),
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
      textTheme: dark
          ? theme.textTheme.apply(
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            )
          : null,
      cardTheme: theme.cardTheme.copyWith(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: const Color(0x29173E2C),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

extension HomeSurfaceAccent on ColorScheme {
  Color get surfaceAccent => brightness == Brightness.dark
      ? (primary.computeLuminance() >= 0.25 ? primary : secondary)
      : (onPrimary == Colors.white ? primary : onPrimary);
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
  const HomeAppBarTitle(this.title, this.subtitle, {super.key, this.icon});

  final String title;
  final String subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 23),
                const SizedBox(width: 8),
              ],
              Flexible(
                  child: Text(title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                      ))),
            ],
          ),
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

Color doseStatusInk(ColorScheme scheme, String? status) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (status) {
    'taken' => dark ? const Color(0xFF9BD69D) : const Color(0xFF2E7D32),
    'late' => dark ? const Color(0xFFFFD27A) : const Color(0xFF966500),
    'skipped' => scheme.onSurfaceVariant,
    _ => scheme.surfaceAccent,
  };
}

class HomeHeaderBackground extends StatelessWidget {
  const HomeHeaderBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final teal = accent == HomePalette.defaultCustomColor;
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.18, 0.6, 1],
            colors: [
              accent,
              teal
                  ? const Color(0xFF117C72)
                  : Color.alphaBlend(scheme.onPrimary.withAlpha(8), accent),
              teal
                  ? const Color(0xFF0B665D)
                  : Color.alphaBlend(scheme.onPrimary.withAlpha(16), accent),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final diameter in [170.0, 220.0, 272.0])
              Positioned(
                right: 38 - diameter / 2,
                top: 36 - diameter / 2,
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          scheme.onPrimary.withAlpha(diameter == 170 ? 25 : 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HomePaletteSwatch extends StatelessWidget {
  const HomePaletteSwatch({
    super.key,
    required this.palette,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final HomePalette palette;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hex = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? scheme.surfaceAccent : Colors.transparent,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: scheme.outline.withAlpha(90)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: selected || palette == HomePalette.custom
                      ? Icon(
                          selected ? Icons.check : Icons.add,
                          size: 16,
                          color: color.computeLuminance() > 0.179
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
              ),
              Text(palette.label,
                  style: Theme.of(context).textTheme.labelSmall),
              Text('#$hex',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 9,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
