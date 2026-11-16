import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/user_model.dart';

Future<DeliveryAddress?> showDeliveryAddressEditor(
  BuildContext context, {
  DeliveryAddress? initial,
}) {
  return showDialog<DeliveryAddress>(
    context: context,
    builder: (_) => _DeliveryAddressEditor(initial: initial),
  );
}

class DeliveryAddressBook extends StatelessWidget {
  const DeliveryAddressBook({
    super.key,
    required this.addresses,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<DeliveryAddress> addresses;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<DeliveryAddress> onEdit;
  final ValueChanged<DeliveryAddress> onDelete;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final address in addresses)
            Card(
              color: address.id == selectedId
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                leading: Icon(
                  address.id == selectedId
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: address.id == selectedId
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(
                  address.label.isEmpty ? 'عنوان التوصيل' : address.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [address.city, address.address]
                      .where((value) => value.trim().isNotEmpty)
                      .join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelect(address.id),
                trailing: PopupMenuButton<String>(
                  tooltip: 'إدارة العنوان',
                  onSelected: (action) =>
                      action == 'edit' ? onEdit(address) : onDelete(address),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('إضافة عنوان جديد'),
          ),
        ],
      );
}

class _DeliveryAddressEditor extends StatefulWidget {
  const _DeliveryAddressEditor({this.initial});

  final DeliveryAddress? initial;

  @override
  State<_DeliveryAddressEditor> createState() => _DeliveryAddressEditorState();
}

class _DeliveryAddressEditorState extends State<_DeliveryAddressEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _city = TextEditingController(text: widget.initial?.city ?? '');
  late final _address =
      TextEditingController(text: widget.initial?.address ?? '');
  late final _locationCoordinates = TextEditingController(
    text: widget.initial?.locationCoordinates ?? '',
  );
  bool _isLocating = false;

  @override
  void dispose() {
    _label.dispose();
    _city.dispose();
    _address.dispose();
    _locationCoordinates.dispose();
    super.dispose();
  }

  Future<void> _setCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('يرجى تفعيل خدمة الموقع في الجهاز');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('يرجى السماح للتطبيق بالوصول إلى موقعك');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      _locationCoordinates.text = '${position.latitude.toStringAsFixed(6)}, '
          '${position.longitude.toStringAsFixed(6)}';
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorMessage.from(error))),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      DeliveryAddress(
        id: widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        label: _label.text.trim(),
        city: _city.text.trim(),
        address: _address.text.trim(),
        locationCoordinates: _locationCoordinates.text.trim().isEmpty
            ? null
            : _locationCoordinates.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'إضافة عنوان' : 'تعديل العنوان'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'اسم العنوان'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل اسمًا مثل المنزل أو العمل'
                      : null,
                ),
                TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'المدينة'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل المدينة'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationCoordinates,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'إحداثيات الموقع',
                    hintText: 'اختياري',
                    prefixIcon: Icon(Icons.my_location_rounded),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _isLocating ? null : _setCurrentLocation,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(
                      _isLocating
                          ? 'جارٍ تحديد الموقع...'
                          : 'تحديد الموقع الحالي',
                    ),
                  ),
                ),
                TextFormField(
                  controller: _address,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'العنوان التفصيلي'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل العنوان التفصيلي'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(onPressed: _save, child: const Text('حفظ العنوان')),
        ],
      );
}
