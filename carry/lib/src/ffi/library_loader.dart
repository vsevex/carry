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
    // Try different locations for Windows
    final locations = [
      // Same directory as executable (installed/bundled)
      'carry_engine.dll',
      // Relative to engine build (from package root)
      '${Directory.current.path}/../engine/target/release/carry_engine.dll',
      // Relative to engine build (from example app)
      '${Directory.current.path}/../../engine/target/release/carry_engine.dll',
      // Workspace root target directory
      '${Directory.current.path}/../target/release/carry_engine.dll',
    ];

    for (final location in locations) {
      try {
        return DynamicLibrary.open(location);
      } catch (_) {
        continue;
      }
    }

    throw UnsupportedError(
      'Could not load carry_engine.dll. '
      'Make sure it is built (cargo build --release in engine/) '
      'and available in one of the expected locations.',
    );
  }

  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Singleton instance of the native library.
final DynamicLibrary _library = loadCarryLibrary();

/// Get the loaded native library.
DynamicLibrary get carryLibrary => _library;
