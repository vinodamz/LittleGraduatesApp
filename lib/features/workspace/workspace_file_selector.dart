import 'package:file_selector/file_selector.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Android's WebView has no default upload picker. In
/// webview_flutter_android 4.14.1, setOnShowFileSelector enables the native
/// onShowFileChooser callback (android_webview_controller.dart:629).
///
/// file_selector_android uses ACTION_OPEN_DOCUMENT and copies only the files
/// the user selects into its cache. No camera/microphone grants are needed.
/// https://pub.dev/packages/file_selector
class WorkspaceFileSelector {
  bool _selecting = false;

  Future<List<String>> select(FileSelectorParams params) async {
    if (_selecting || params.mode == FileSelectorMode.save) return [];
    _selecting = true;
    try {
      final groups = workspaceFileTypes(params.acceptTypes);
      final List<XFile> files;
      if (params.mode == FileSelectorMode.openMultiple) {
        files = await openFiles(acceptedTypeGroups: groups);
      } else {
        final file = await openFile(acceptedTypeGroups: groups);
        files = file == null ? [] : [file];
      }
      // Android's selector returns local cache paths, not provider URLs.
      // Encode spaces, #, and non-ASCII names for WebView's Uri.parse bridge.
      return files.map((file) {
        if (!file.path.startsWith('/')) {
          throw const FormatException('The selected file has no local path.');
        }
        return Uri.file(file.path).toString();
      }).toList();
    } finally {
      _selecting = false;
    }
  }
}

/// HTML accept can contain extensions, MIME types, or comma-separated groups.
/// Filters guide the picker; the existing server still validates uploads.
List<XTypeGroup> workspaceFileTypes(List<String> acceptTypes) {
  final types = acceptTypes
      .expand((value) => value.split(','))
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (types.isEmpty || types.contains('*/*') || types.contains('*')) return [];

  final extensions = <String>{};
  final mimeTypes = <String>{};
  for (final type in types) {
    if (RegExp(r'^\.[a-z0-9][a-z0-9._+-]*$').hasMatch(type)) {
      extensions.add(type.substring(1));
    } else if (RegExp(
      r'^[a-z0-9!#$&^_.+-]+/(\*|[a-z0-9!#$&^_.+-]+)$',
    ).hasMatch(type)) {
      mimeTypes.add(type);
    }
  }
  if (extensions.isEmpty && mimeTypes.isEmpty) return [];
  return [
    XTypeGroup(
      label: 'Files',
      extensions: extensions.isEmpty ? null : extensions.toList(),
      mimeTypes: mimeTypes.isEmpty ? null : mimeTypes.toList(),
    ),
  ];
}
