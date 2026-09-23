import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import 'images.dart';
import 'reading.dart';

class SavedPhoto {
  const SavedPhoto(
    this.id,
    this.photo,
    this.thumbnail,
    this.capturedAt,
    this.reading,
    this.rawText,
    this.ocrMs,
    this.enhanced,
  );
  final int id;
  final Uint8List photo, thumbnail;
  final DateTime capturedAt;
  final String reading, rawText;
  final int? ocrMs;
  final bool enhanced;
  factory SavedPhoto.fromMap(Map value) => SavedPhoto(
    value['id'] as int,
    Uint8List.fromList((value['photo'] as List).cast<int>()),
    Uint8List.fromList((value['thumbnail'] as List).cast<int>()),
    DateTime.fromMillisecondsSinceEpoch(value['capturedAt'] as int),
    value['reading'] as String,
    value['rawText'] as String,
    value['ocrMs'] as int?,
    value['enhanced'] as bool,
  );
}

class PhotoRepository {
  PhotoRepository(this.factory, {this.name = 'moisture-meter'});
  final IdbFactory factory;
  final String name;
  Future<Database>? _database;
  Future<Database> _open() async {
    try {
      return await (_database ??= factory.open(
        name,
        version: 1,
        onUpgradeNeeded: (event) {
          event.database.createObjectStore(
            'photos',
            keyPath: 'id',
            autoIncrement: true,
          );
        },
      ));
    } catch (_) {
      _database = null;
      rethrow;
    }
  }

  Future<void> save(
    Capture capture,
    String reading,
    String rawText,
    int? ocrMs,
    bool enhanced,
  ) async {
    if (parseReading(reading) == null) {
      throw ArgumentError('Enter one decimal reading.');
    }
    final db = await _open();
    final txn = db.transaction('photos', idbModeReadWrite);
    await Future.wait<Object?>([
      txn.objectStore('photos').add({
        'photo': capture.photo,
        'thumbnail': capture.thumbnail,
        'capturedAt': capture.capturedAt.millisecondsSinceEpoch,
        'reading': reading.trim(),
        'rawText': rawText,
        'ocrMs': ocrMs,
        'enhanced': enhanced,
      }),
      txn.completed,
    ]);
  }

  Future<void> updateImage(int id, Uint8List photo, Uint8List thumbnail) async {
    final db = await _open();
    final txn = db.transaction('photos', idbModeReadWrite);
    final store = txn.objectStore('photos');
    await Future.wait<Object?>([
      () async {
        final record = await store.getObject(id) as Map?;
        if (record == null) throw StateError('Photo no longer exists.');
        await store.put({...record, 'photo': photo, 'thumbnail': thumbnail});
      }(),
      txn.completed,
    ]);
  }

  Future<List<SavedPhoto>> list() async {
    final db = await _open();
    final txn = db.transaction('photos', idbModeReadOnly);
    final results = await Future.wait<Object?>([
      txn.objectStore('photos').getAll(),
      txn.completed,
    ]);
    final items = (results.first as List)
        .map((v) => SavedPhoto.fromMap(v as Map))
        .toList();
    items.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return items;
  }

  Future<void> close() async {
    if (_database != null) (await _database!).close();
  }
}
