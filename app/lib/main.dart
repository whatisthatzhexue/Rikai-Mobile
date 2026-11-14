import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'core/theme/font_licenses.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledFontLicenses();
  runApp(const BootstrapApp());
}
