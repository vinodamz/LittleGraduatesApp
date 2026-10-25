import 'dart:js_interop';

@JS('lgStore.read')
external JSPromise<JSString> _read(JSString key);
@JS('lgStore.write')
external JSPromise<JSAny?> _write(JSString key, JSString value);

@JS('lgStore.lock')
external JSPromise<JSBoolean> _lock(JSString owner);
@JS('lgStore.release')
external void _release(JSString owner);

class BrowserStore {
  Future<bool> lock(String owner) async =>
      (await _lock(owner.toJS).toDart).toDart;
  void release(String owner) => _release(owner.toJS);
  Future<String> read(String key) async =>
      (await _read(key.toJS).toDart).toDart;
  Future<void> write(String key, String value) async {
    await _write(key.toJS, value.toJS).toDart;
  }
}
