import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb_browser.dart';

@JS('meterOfflineStatus')
external JSString _status();
@JS('meterRetryOffline')
external void _retryOffline();
void retryOffline() => _retryOffline();
@JS('URL.revokeObjectURL')
external void _revoke(JSString url);
String offlineStatus() => _status().toDart;
void revokeCaptureUrl(String url) => _revoke(url.toJS);
IdbFactory browserDatabaseFactory() => idbFactoryNative;

@JS('navigator.storage.estimate')
external JSPromise<_StorageEstimate> _estimateStorage();

extension type _StorageEstimate(JSObject _) implements JSObject {
  external double? get usage;
  external double? get quota;
}

Future<double?> browserStorageUsage() async {
  try {
    final estimate = await _estimateStorage().toDart;
    final usage = estimate.usage;
    final quota = estimate.quota;
    if (usage == null ||
        quota == null ||
        !usage.isFinite ||
        !quota.isFinite ||
        usage < 0 ||
        quota <= 0) {
      return null;
    }
    debugPrint(quota.toString());
    return (usage / quota).clamp(0.0, 1.0);
  } catch (_) {
    return null;
  }
}
