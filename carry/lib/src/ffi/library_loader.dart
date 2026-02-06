import 'dart:ffi';
import 'dart:io';

/// Loads the native Carry engine library for the current platform.
DynamicLibrary loadCarryLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libcarry_engine.so');
  } else if (Platform.isIOS) {
    // iOS uses static linking via framework
    return DynamicLibrary.process();
  } else if (Platform.isMacOS) {
    // Try different locations for macOS
    final locations = [
      // Development: relative to workspace
      'libcarry_engine.dylib',
      // Installed in app bundle
      '@executable_path/../Frameworks/libcarry_engine.dylib',
      // System location
      '/usr/local/lib/libcarry_engine.dylib',
      // Relative to engine build (from package root)
      '${Directory.current.path}/../engine/target/release/libcarry_engine.dylib',
      // Relative to engine build (from example app)
      '${Directory.current.path}/../../engine/target/release/libcarry_engine.dylib',
    ];

    for (final location in locations) {
      try {
        return DynamicLibrary.open(location);
      } catch (_) {
        continue;
      }
    }

    throw UnsupportedError(
      'Could not load libcarry_engine.dylib. '
      'Make sure it is built and available in one of the expected locations.',
    );
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libcarry_engine.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('carry_engine.dll');
  }

  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Singleton instance of the native library.
final DynamicLibrary _library = loadCarryLibrary();

/// Get the loaded native library.
DynamicLibrary get carryLibrary => _library;
