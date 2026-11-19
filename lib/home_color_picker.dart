import 'package:flutter/material.dart';

import 'home_style.dart';

class HomeColorPicker extends StatefulWidget {
  const HomeColorPicker({super.key, required this.initialColor});

  final Color initialColor;

  @override
  State<HomeColorPicker> createState() => _HomeColorPickerState();
}

class _HomeColorPickerState extends State<HomeColorPicker> {
  late HSVColor _selection = HSVColor.fromColor(widget.initialColor);

  Widget _colorControl({
    required Key key,
    required Gradient gradient,
    required Alignment marker,
    required ValueChanged<Offset> onPick,
    Gradient? overlay,
  }) {
    return Builder(builder: (context) {
      void pick(Offset position) {
        final size = context.size!;
        setState(() {
          onPick(Offset(
            (position.dx / size.width).clamp(0.0, 1.0),
            (position.dy / size.height).clamp(0.0, 1.0),
          ));
        });
      }

      return GestureDetector(
        key: key,
        onTapDown: (details) => pick(details.localPosition),
        onPanStart: (details) => pick(details.localPosition),
        onPanUpdate: (details) => pick(details.localPosition),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: overlay,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Align(
              alignment: marker,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, blurRadius: 2)
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _selection.toColor();
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Chọn màu tùy chỉnh'),
      scrollable: true,
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              children: [
                for (final palette in HomePalette.values)
                  if (palette != HomePalette.custom)
                    IconButton(
                      tooltip: palette.label,
                      onPressed: () => setState(() => _selection =
                          HSVColor.fromColor(Color(palette.primary))),
                      icon: _swatch(
                        Color(palette.primary),
                        scheme.outline,
                        selected: color == Color(palette.primary),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: _colorControl(
                      key: const Key('customColorHue'),
                      gradient: const LinearGradient(colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ]),
                      marker: Alignment(_selection.hue / 180 - 1, 0),
                      onPick: (point) =>
                          _selection = _selection.withHue(point.dx * 360),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _swatch(color, scheme.outline,
                    key: const Key('customColorPreview')),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: AspectRatio(
                aspectRatio: 1,
                child: _colorControl(
                  key: const Key('customColorSaturationValue'),
                  gradient: LinearGradient(colors: [
                    Colors.white,
                    HSVColor.fromAHSV(1, _selection.hue, 1, 1).toColor(),
                  ]),
                  overlay: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Colors.black],
                  ),
                  marker: Alignment(
                    2 * _selection.saturation - 1,
                    1 - 2 * _selection.value,
                  ),
                  onPick: (point) => _selection = _selection
                      .withSaturation(point.dx)
                      .withValue(1 - point.dy),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Lưu'),
        ),
      ],
    );
  }

  Widget _swatch(Color color, Color outline,
          {bool selected = false, Key? key}) =>
      Container(
        key: key,
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: outline),
        ),
        child: selected
            ? Icon(Icons.check,
                size: 16,
                color: color.computeLuminance() > 0.179
                    ? Colors.black
                    : Colors.white)
            : null,
      );
}
