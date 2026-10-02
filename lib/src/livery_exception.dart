import 'dart:io';

/// Every problem livery reports to the user instead of crashing: malformed
/// YAML, an unknown key, a section that does not exist, a file that cannot be
/// written.
///
/// [source] is the file the problem comes from and [path] the location inside
/// it, such as `outputs.android.format`.
class LiveryException implements Exception {
  const LiveryException(this.message, {this.source, this.path});

  final String message;
  final String? source;
  final String? path;

  /// This exception, with [source] and [path] filled in where it has none.
  ///
  /// Lets code that knows nothing about the manifest throw, and the caller that
  /// does know add the breadcrumbs.
  LiveryException located({required String source, required String path}) =>
      LiveryException(message, source: this.source ?? source, path: this.path ?? path);

  @override
  String toString() {
    final buffer = StringBuffer();
    if (source != null) {
      buffer.write('$source: ');
    }
    if (path != null) {
      buffer.write('[$path] ');
    }
    buffer.write(message);

    return buffer.toString();
  }
}

/// The operating system's reason for [error], without Dart's wrapping.
String describeFileSystemError(FileSystemException error) => error.osError?.message ?? error.message;
