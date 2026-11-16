import 'package:flutter/material.dart';

const productColorSuggestions = [
  'أسود',
  'أبيض',
  'أحمر',
  'أزرق',
  'أخضر',
  'وردي',
  'بيج',
  'بني',
  'رمادي',
  'ذهبي',
  'فضي',
  'برتقالي',
  'أصفر',
  'بنفسجي',
  'كحلي',
  'تركوازي',
  'سماوي',
  'زيتي',
  'عنابي',
  'موف',
  'نعناعي',
  'كريمي',
  'نحاسي',
];

Color productColorValue(String name) {
  final value = name.trim().toLowerCase();
  const namedColors = {
    'أسود': Colors.black,
    'black': Colors.black,
    'أبيض': Color(0xFFF8FAFC),
    'white': Color(0xFFF8FAFC),
    'أحمر': Color(0xFFDC2626),
    'red': Color(0xFFDC2626),
    'أزرق': Color(0xFF2563EB),
    'blue': Color(0xFF2563EB),
    'أخضر': Color(0xFF16A34A),
    'green': Color(0xFF16A34A),
    'وردي': Color(0xFFEC4899),
    'pink': Color(0xFFEC4899),
    'بيج': Color(0xFFD6C2A1),
    'beige': Color(0xFFD6C2A1),
    'بني': Color(0xFF92400E),
    'brown': Color(0xFF92400E),
    'رمادي': Color(0xFF6B7280),
    'gray': Color(0xFF6B7280),
    'grey': Color(0xFF6B7280),
    'ذهبي': Color(0xFFD4AF37),
    'gold': Color(0xFFD4AF37),
    'فضي': Color(0xFFCBD5E1),
    'silver': Color(0xFFCBD5E1),
    'برتقالي': Color(0xFFF97316),
    'orange': Color(0xFFF97316),
    'أصفر': Color(0xFFFACC15),
    'yellow': Color(0xFFFACC15),
    'بنفسجي': Color(0xFF7C3AED),
    'purple': Color(0xFF7C3AED),
    'كحلي': Color(0xFF1E3A8A),
    'navy': Color(0xFF1E3A8A),
    'تركوازي': Color(0xFF0D9488),
    'turquoise': Color(0xFF0D9488),
    'سماوي': Color(0xFF38BDF8),
    'sky': Color(0xFF38BDF8),
    'زيتي': Color(0xFF4D7C0F),
    'olive': Color(0xFF4D7C0F),
    'عنابي': Color(0xFF9F1239),
    'burgundy': Color(0xFF9F1239),
    'موف': Color(0xFFA855F7),
    'mauve': Color(0xFFA855F7),
    'نعناعي': Color(0xFF6EE7B7),
    'mint': Color(0xFF6EE7B7),
    'كريمي': Color(0xFFFFF7ED),
    'cream': Color(0xFFFFF7ED),
    'نحاسي': Color(0xFFB45309),
    'copper': Color(0xFFB45309),
  };

  final hexMatch = RegExp(r'#?([0-9a-f]{6})').firstMatch(value);
  final hex = hexMatch?.group(1);
  if (hex != null) {
    return Color(int.parse('FF$hex', radix: 16));
  }

  return namedColors[value] ?? const Color(0xFFE2E8F0);
}

Future<String?> showCustomProductColorDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _CustomProductColorDialog(),
  );
}

class _CustomProductColorDialog extends StatefulWidget {
  const _CustomProductColorDialog();

  @override
  State<_CustomProductColorDialog> createState() =>
      _CustomProductColorDialogState();
}

class _CustomProductColorDialogState extends State<_CustomProductColorDialog> {
  final _nameController = TextEditingController();
  final _hexController = TextEditingController(text: '#2563EB');
  HSVColor _color = HSVColor.fromColor(const Color(0xFF2563EB));

  @override
  void dispose() {
    _nameController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _setColor(HSVColor color) {
    setState(() {
      _color = color;
      _hexController.text = _toHex(color.toColor());
    });
  }

  void _setHex(String value) {
    final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value.trim());
    if (match == null) return;
    final parsed = Color(int.parse('FF${match.group(1)}', radix: 16));
    setState(() => _color = HSVColor.fromColor(parsed));
  }

  String _toHex(Color color) =>
      '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop('$name (${_toHex(_color.toColor())})');
  }

  @override
  Widget build(BuildContext context) {
    final color = _color.toColor();
    return AlertDialog(
      title: const Text('إضافة لون مخصص'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'اسم اللون',
                hintText: 'مثال: أزرق سماوي',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 18),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              alignment: Alignment.center,
              child: Text(
                _toHex(color),
                style: TextStyle(
                  color: color.computeLuminance() > 0.55
                      ? Colors.black
                      : Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SaturationValuePicker(
              color: _color,
              onPositionChanged: (saturation, value) =>
                  _setColor(_color.withSaturation(saturation).withValue(value)),
            ),
            const SizedBox(height: 12),
            _HuePicker(
              hue: _color.hue,
              onChanged: (hue) => _setColor(_color.withHue(hue)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _hexController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'كود اللون HEX',
                hintText: '#2563EB',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              onChanged: _setHex,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة اللون'),
        ),
      ],
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({
    required this.color,
    required this.onPositionChanged,
  });

  final HSVColor color;
  final void Function(double saturation, double value) onPositionChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.8,
      child: GestureDetector(
        onPanDown: (details) => _update(details.localPosition, context),
        onPanUpdate: (details) => _update(details.localPosition, context),
        child: CustomPaint(
          painter: _SaturationValuePainter(color),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  void _update(Offset position, BuildContext context) {
    final size = context.size;
    if (size == null) return;
    final saturation = (position.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - position.dy / size.height).clamp(0.0, 1.0);
    onPositionChanged(saturation, value);
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.color);
  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor();
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [Colors.white, hueColor],
          ).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(rect));
    final point =
        Offset(color.saturation * size.width, (1 - color.value) * size.height);
    canvas.drawCircle(point, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
        point,
        7,
        Paint()
          ..color = color.toColor()
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HuePicker extends StatelessWidget {
  const _HuePicker({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: GestureDetector(
        onPanDown: (details) => _update(details.localPosition, context),
        onPanUpdate: (details) => _update(details.localPosition, context),
        child: CustomPaint(painter: const _HuePainter()),
      ),
    );
  }

  void _update(Offset position, BuildContext context) {
    final width = context.size?.width ?? 1;
    onChanged((position.dx / width * 360).clamp(0.0, 360.0));
  }
}

class _HuePainter extends CustomPainter {
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => false;
}

class ProductColorSwatch extends StatelessWidget {
  const ProductColorSwatch({
    super.key,
    required this.name,
    this.selected = false,
    this.onTap,
    this.showName = true,
  });

  final String name;
  final bool selected;
  final VoidCallback? onTap;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final color = productColorValue(name);
    final isLight = color.computeLuminance() > 0.72;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 48 : 42,
          height: selected ? 48 : 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? const Color(0xFF111827)
                  : (isLight ? const Color(0xFFCBD5E1) : Colors.transparent),
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x22111827),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(Icons.check_rounded,
                  size: 25, color: isLight ? Colors.black : Colors.white)
              : null,
        ),
        if (showName) ...[
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ],
    );

    return onTap == null
        ? content
        : Semantics(
            button: true,
            selected: selected,
            label: 'اللون $name',
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: content,
              ),
            ),
          );
  }
}
