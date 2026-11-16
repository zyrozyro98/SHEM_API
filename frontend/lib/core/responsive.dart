import 'package:flutter/widgets.dart';

class Responsive {
  // Breakpoints are customizable
  static int columnsForWidth(double width,
      {int mobile = 2, int tablet = 3, int desktop = 4}) {
    if (width >= 1100) return desktop;
    if (width >= 700) return tablet;
    return mobile;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100;
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 700 &&
      MediaQuery.of(context).size.width < 1100;
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 700;
}
