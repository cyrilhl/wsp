import 'package:idb_shim/idb.dart';

IdbFactory browserDatabaseFactory() =>
    throw UnsupportedError('Use a web browser.');
String offlineStatus() =>
    'Offline setup is available in the release web build.';
void retryOffline() {}
void revokeCaptureUrl(String url) {}
Future<double?> browserStorageUsage() async => null;
