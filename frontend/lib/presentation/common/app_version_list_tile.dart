import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionListTile extends StatelessWidget {
  const AppVersionListTile({super.key});

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final subtitle = snapshot.hasError
            ? 'تعذر تحميل الإصدار'
            : snapshot.hasData
                ? 'الإصدار ${snapshot.data!.version}'
                : 'جارٍ تحميل الإصدار...';
        return ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('إصدار التطبيق'),
          subtitle: Text(subtitle),
        );
      },
    );
  }
}
