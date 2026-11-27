import 'dart:async';

// The fake exercises file_selector's real single/multiple dispatch.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_graduates/features/workspace/workspace_file_selector.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class TestFilePicker extends FileSelectorPlatform {
  XFile? single;
  List<XFile> multiple = [];
  List<XTypeGroup>? groups;
  int singleCalls = 0;
  int multipleCalls = 0;
  Object? failure;
  Completer<XFile?>? pending;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    singleCalls++;
    groups = acceptedTypeGroups;
    if (failure != null) throw failure!;
    return pending == null ? single : await pending!.future;
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    multipleCalls++;
    groups = acceptedTypeGroups;
    return multiple;
  }
}

FileSelectorParams request({
  List<String> accept = const [],
  bool multiple = false,
  bool capture = false,
  FileSelectorMode? mode,
}) => FileSelectorParams(
  acceptTypes: accept,
  isCaptureEnabled: capture,
  mode:
      mode ??
      (multiple ? FileSelectorMode.openMultiple : FileSelectorMode.open),
);

void main() {
  late TestFilePicker picker;
  late WorkspaceFileSelector selector;
  late FileSelectorPlatform previous;
  setUp(() {
    previous = FileSelectorPlatform.instance;
    picker = TestFilePicker();
    FileSelectorPlatform.instance = picker;
    selector = WorkspaceFileSelector();
  });
  tearDown(() => FileSelectorPlatform.instance = previous);

  test(
    'single document uses system picker and returns an encoded file URI',
    () async {
      picker.single = XFile('/cache/Child report #1 résumé.pdf');
      final result = await selector.select(
        request(accept: ['application/pdf']),
      );
      expect(picker.singleCalls, 1);
      expect(picker.multipleCalls, 0);
      expect(picker.groups!.single.mimeTypes, ['application/pdf']);
      expect(result.single, startsWith('file:///cache/'));
      expect(result.single, contains('%23'));
      expect(Uri.parse(result.single).toFilePath(), picker.single!.path);
    },
  );

  test(
    'multiple photos, video and documents retain all selected files',
    () async {
      picker.multiple = [
        XFile('/cache/photo.jpg'),
        XFile('/cache/video.mp4'),
        XFile('/cache/cv.docx'),
      ];
      final result = await selector.select(
        request(multiple: true, accept: ['image/*,video/*,.docx']),
      );
      expect(picker.singleCalls, 0);
      expect(picker.multipleCalls, 1);
      expect(picker.groups!.single.mimeTypes, ['image/*', 'video/*']);
      expect(picker.groups!.single.extensions, ['docx']);
      expect(
        result.map((value) => Uri.parse(value).toFilePath()),
        picker.multiple.map((file) => file.path),
      );
    },
  );

  test(
    'existing voice file uses picker even when capture is requested',
    () async {
      picker.single = XFile('/cache/voice.m4a');
      expect(
        await selector.select(request(accept: ['audio/*,.m4a'], capture: true)),
        ['file:///cache/voice.m4a'],
      );
      expect(picker.singleCalls, 1);
      expect(picker.groups!.single.mimeTypes, ['audio/*']);
    },
  );

  test('accept filters handle MIME/extensions, whitespace and duplicates', () {
    final group = workspaceFileTypes([
      ' .PDF, .docx ',
      'image/jpeg',
      'APPLICATION/PDF',
      '.pdf',
    ]).single;
    expect(group.extensions, ['pdf', 'docx']);
    expect(group.mimeTypes, ['image/jpeg', 'application/pdf']);
  });

  test(
    'absent, wildcard and invalid accept values use the general chooser',
    () {
      for (final accept in <List<String>>[
        [],
        [''],
        ['*/*', '.pdf'],
        ['*'],
        ['not a type', 'file:///secret'],
      ]) {
        expect(workspaceFileTypes(accept), isEmpty, reason: '$accept');
      }
    },
  );

  test('cancelled single and multiple selections return no files', () async {
    expect(await selector.select(request()), isEmpty);
    expect(await selector.select(request(multiple: true)), isEmpty);
  });

  test('save requests do not launch a chooser or expose any files', () async {
    expect(
      await selector.select(request(mode: FileSelectorMode.save)),
      isEmpty,
    );
    expect(picker.singleCalls + picker.multipleCalls, 0);
  });

  test('concurrent requests cannot open a second chooser', () async {
    picker.pending = Completer<XFile?>();
    final first = selector.select(request());
    expect(await selector.select(request(multiple: true)), isEmpty);
    expect(picker.singleCalls, 1);
    expect(picker.multipleCalls, 0);
    picker.pending!.complete(XFile('/cache/first.pdf'));
    expect(await first, ['file:///cache/first.pdf']);
  });

  test('picker failure releases the lock for a subsequent selection', () async {
    picker.failure = PlatformException(code: 'unavailable');
    await expectLater(
      selector.select(request()),
      throwsA(isA<PlatformException>()),
    );
    picker.failure = null;
    picker.single = XFile('/cache/retry.pdf');
    expect(await selector.select(request()), ['file:///cache/retry.pdf']);
  });

  test('only local picker paths can become WebView file URIs', () async {
    for (final path in [
      '',
      'relative.pdf',
      'https://example.test/file.pdf',
      'content://unexpected/file',
    ]) {
      picker.single = XFile(path);
      await expectLater(selector.select(request()), throwsFormatException);
    }
    picker.single = XFile('/cache/valid.pdf');
    expect(await selector.select(request()), ['file:///cache/valid.pdf']);
  });
}
