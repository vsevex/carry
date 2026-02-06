import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/carry_devtools_extension.dart';

void main() => runApp(const CarryDevToolsExtensionApp());

class CarryDevToolsExtensionApp extends StatelessWidget {
  const CarryDevToolsExtensionApp({super.key});

  @override
  Widget build(BuildContext context) => const DevToolsExtension(
        child: CarryDebugPanel(),
      );
}
