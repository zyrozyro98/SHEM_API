import 'package:flutter/material.dart';
import 'package:she_m_app/data/services/driver_service.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() =>
      _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedRegion = 'صنعاء';
  String _selectedVehicle = 'دراجة نارية';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final driver = DriverService.registerDriver(
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      region: _selectedRegion,
      vehicleType: _selectedVehicle,
      isAvailable: true,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'تم تسجيل المندوب ${driver.fullName} بنجاح في ${driver.region}'),
      ),
    );

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل المندوب')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إنشاء حساب مندوب',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل الاسم'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل رقم الهاتف'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRegion,
                  decoration: const InputDecoration(
                    labelText: 'المنطقة',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'صنعاء',
                    'عدن',
                    'تعز',
                  ]
                      .map((region) =>
                          DropdownMenuItem(value: region, child: Text(region)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedRegion = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedVehicle,
                  decoration: const InputDecoration(
                    labelText: 'وسيلة التوصيل',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['دراجة نارية', 'سيارة صغيرة']
                      .map((vehicle) => DropdownMenuItem(
                          value: vehicle, child: Text(vehicle)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedVehicle = value);
                    }
                  },
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('تسجيل المندوب'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
