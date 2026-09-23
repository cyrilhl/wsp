import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:wsp/services/images.dart';
import 'package:wsp/services/photos.dart';
import 'package:wsp/services/reading.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'mirrored camera pixels are normalized within the landscape crop',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 50, 80),
        Paint()..color = const Color(0xffff0000),
      );
      canvas.drawRect(
        const Rect.fromLTWH(50, 0, 50, 80),
        Paint()..color = const Color(0xff0000ff),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 80);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final capture = await ImageService().prepare(
        data!.buffer.asUint8List(),
        mirrored: true,
        viewportSize: const Size(100, 200),
      );
      final codec = await ui.instantiateImageCodec(capture.crop);
      final cropped = (await codec.getNextFrame()).image;
      expect(cropped.width, 34);
      expect(cropped.height, 17);
      final pixels = (await cropped.toByteData())!.buffer.asUint8List();
      expect(pixels.sublist(0, 4), [0, 0, 255, 255]);
      expect(pixels.sublist(33 * 4, 34 * 4), [255, 0, 0, 255]);
      cropped.dispose();
      codec.dispose();
      image.dispose();
      picture.dispose();
    },
  );
  test('one complete number, preserving precision and rejecting ambiguity', () {
    for (final value in ['0', '12.50', '-3.2', '000.1']) {
      expect(parseReading(' $value\n'), value);
    }
    for (final value in [
      '',
      '12 34',
      '12\n34',
      '1.2.3',
      '12%',
      'O.5',
      '1e2',
      '.',
      '12.',
    ]) {
      expect(parseReading(value), isNull);
    }
  });
  test('viewfinder stays landscape and centered in either orientation', () {
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      final frame = viewfinderFor(size);
      expect(frame.width / frame.height, 2);
      expect(frame.center.dx, closeTo(size.width / 2, .001));
      expect(frame.center.dy, closeTo(size.height / 2, .001));
      expect((Offset.zero & size).contains(frame.topLeft), isTrue);
      expect((Offset.zero & size).contains(frame.bottomRight), isTrue);
    }
  });
  test(
    'full-screen portrait crop accounts for hidden landscape image edges',
    () {
      const viewport = Size(400, 800);
      const image = Size(1600, 1200);
      final bounds = cameraPreviewBounds(viewport, image);
      final crop = imageCrop(viewfinderFor(viewport), bounds, image);
      expect(crop.left, closeTo(548, .001));
      expect(crop.top, closeTo(474, .001));
      expect(crop.width, closeTo(504, .001));
      expect(crop.height, closeTo(252, .001));
    },
  );
  test('portrait image crop accounts for hidden top and bottom edges', () {
    const viewport = Size(400, 600);
    const image = Size(1200, 2400);
    final crop = imageCrop(
      viewfinderFor(viewport),
      cameraPreviewBounds(viewport, image),
      image,
    );
    expect(crop, const Rect.fromLTWH(96, 948, 1008, 504));
  });
  test('legacy records with stored crops remain readable', () async {
    final factory = newIdbFactoryMemory();
    final db = await factory.open(
      'moisture-meter',
      version: 1,
      onUpgradeNeeded: (event) => event.database.createObjectStore(
        'photos',
        keyPath: 'id',
        autoIncrement: true,
      ),
    );
    final txn = db.transaction('photos', idbModeReadWrite);
    await txn.objectStore('photos').add({
      'photo': [1, 2, 3],
      'crop': [4, 5, 6],
      'thumbnail': [7, 8, 9],
      'capturedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      'reading': '12.50',
      'rawText': '12.5',
      'ocrMs': 100,
      'enhanced': false,
    });
    await txn.completed;
    db.close();
    final repository = PhotoRepository(factory);
    final photos = await repository.list();
    expect(photos.single.reading, '12.50');
    expect(photos.single.photo, [1, 2, 3]);
    expect(photos.single.thumbnail, [7, 8, 9]);
    await repository.close();
  });
  test(
    'editing replaces image and thumbnail while preserving metadata',
    () async {
      final factory = newIdbFactoryMemory();
      final repository = PhotoRepository(factory);
      final original = Uint8List.fromList([1, 2, 3]);
      final edited = Uint8List.fromList([4, 5, 6]);
      final thumbnail = Uint8List.fromList([7, 8]);
      final date = DateTime(2026, 1, 1);
      await repository.save(
        Capture(original, original, original, date),
        '12.50',
        '12.5',
        120,
        true,
      );
      final id = (await repository.list()).single.id;
      await repository.updateImage(id, edited, thumbnail);
      await repository.close();
      final reopened = PhotoRepository(factory);
      final photo = (await reopened.list()).single;
      expect(photo.id, id);
      expect(photo.photo, edited);
      expect(photo.thumbnail, thumbnail);
      expect(photo.capturedAt, date);
      expect(photo.reading, '12.50');
      expect(photo.rawText, '12.5');
      expect(photo.ocrMs, 120);
      expect(photo.enhanced, isTrue);
      await expectLater(
        reopened.updateImage(id + 1, edited, thumbnail),
        throwsStateError,
      );
      expect(await reopened.list(), hasLength(1));
      await reopened.close();
    },
  );
  test('photos survive repository reopen without storing crops', () async {
    final factory = newIdbFactoryMemory();
    final first = PhotoRepository(factory);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final older = Capture(bytes, bytes, bytes, DateTime(2026, 1, 1));
    final newer = Capture(bytes, bytes, bytes, DateTime(2026, 2, 1));
    await first.save(older, '12.50', '12.5\n', 100, false);
    await first.save(newer, '13', '13', 120, true);
    await first.close();
    final db = await factory.open('moisture-meter');
    final txn = db.transaction('photos', idbModeReadOnly);
    final records = await txn.objectStore('photos').getAll();
    await txn.completed;
    expect(records, hasLength(2));
    for (final record in records) {
      expect((record as Map).containsKey('crop'), isFalse);
    }
    db.close();
    final reopened = PhotoRepository(factory);
    final photos = await reopened.list();
    expect(photos.map((p) => p.reading), ['13', '12.50']);
    expect(photos.last.photo, bytes);
    expect(photos.last.thumbnail, bytes);
    expect(photos.last.rawText, '12.5\n');
    expect(photos.first.enhanced, true);
    await expectLater(
      reopened.save(older, '12 34', '', null, false),
      throwsArgumentError,
    );
    expect((await reopened.list()).length, 2);
    await reopened.close();
  });
}
