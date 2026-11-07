import 'package:flutter/widgets.dart';

/// Galaxy Z Fold 7 düzenleri:
///  * Katlı (dış ekran): ~ 412 dp genişlik -> tek sütun (compact)
///  * Açık (iç ekran): ~ 840+ dp genişlik -> iki sütun (expanded)
/// Eşik, Material 3 "expanded" sınıfı ile uyumludur.
enum SaklazLayout { compact, medium, expanded }

SaklazLayout layoutFor(double width) {
  if (width >= 840) return SaklazLayout.expanded;
  if (width >= 600) return SaklazLayout.medium;
  return SaklazLayout.compact;
}

extension SaklazLayoutX on BuildContext {
  SaklazLayout get saklazLayout => layoutFor(MediaQuery.sizeOf(this).width);
}
