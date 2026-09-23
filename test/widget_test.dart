import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:wsp/main.dart';
import 'package:wsp/services/images.dart';
import 'package:wsp/services/ocr.dart';
import 'package:wsp/services/photos.dart';

final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC',
);
Capture fixture() => Capture(pixel, pixel, pixel, DateTime(2026, 9, 23));

class FakeOcr extends OcrService {
  FakeOcr(this.text);
  final String text;
  @override
  Future<OcrResult> recognize(Uint8List crop, {bool enhanced = true}) async =>
      OcrResult(text, 120);
}

class ControlledRepository extends PhotoRepository {
  ControlledRepository() : super(newIdbFactoryMemory());
  int writes = 0;
  String? confirmed;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> save(
    Capture capture,
    String reading,
    String rawText,
    int? ocrMs,
    bool enhanced,
  ) async {
    writes++;
    confirmed = reading;
    if (fail) throw StateError('Storage unavailable');
    await pending?.future;
  }
}

class EditingRepository extends PhotoRepository {
  EditingRepository() : super(newIdbFactoryMemory());
  bool failUpdate = false;

  @override
  Future<void> updateImage(int id, Uint8List photo, Uint8List thumbnail) async {
    if (failUpdate) throw StateError('Storage unavailable');
    await super.updateImage(id, photo, thumbnail);
  }
}

void main() {
  testWidgets('home opens empty gallery at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MeterApp(repository: PhotoRepository(newIdbFactoryMemory())),
    );
    await tester.tap(find.text('View gallery'));
    await tester.pumpAndSettle();
    expect(
      find.text('No photos yet. Take your first reading.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'gallery shows photo and confirmed value without crop or raw OCR',
    (tester) async {
      final repository = EditingRepository();
      await tester.runAsync(
        () => repository.save(fixture(), '12.50', '12.5', 120, false),
      );
      addTearDown(repository.close);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: GalleryScreen(repository: repository)),
        );
        await repository.list();
      });
      await tester.pumpAndSettle();
      expect(find.text('12.50'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('12.50'));
      await tester.pumpAndSettle();
      expect(find.text('Reading 12.50'), findsOneWidget);
      expect(find.text('12.50'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('VIEWFINDER CROP'), findsNothing);
      expect(find.textContaining('Raw OCR:'), findsNothing);
      await tester.tap(find.byTooltip('Edit photo'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final editor = tester.widget<ProImageEditor>(find.byType(ProImageEditor));
      expect(editor.configs.mainEditor.tools, [
        SubEditorMode.paint,
        SubEditorMode.text,
        SubEditorMode.cropRotate,
        SubEditorMode.tune,
      ]);
      editor.callbacks.onCloseEditor!(EditorMode.main);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ProImageEditor), findsNothing);
      expect(find.text('Reading 12.50'), findsOneWidget);
      final photos = await tester.runAsync(repository.list);
      expect(photos!.single.photo, pixel);
      await tester.tap(find.byTooltip('Edit photo'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final retryEditor = tester.widget<ProImageEditor>(
        find.byType(ProImageEditor),
      );
      repository.failUpdate = true;
      await tester.runAsync(
        () => retryEditor.callbacks.onImageEditingComplete!(pixel),
      );
      retryEditor.callbacks.onCloseEditor!(EditorMode.main);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Save failed'), findsOneWidget);
      expect(find.byType(ProImageEditor), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      repository.failUpdate = false;
      await tester.runAsync(
        () => retryEditor.callbacks.onImageEditingComplete!(pixel),
      );
      retryEditor.callbacks.onCloseEditor!(EditorMode.main);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ProImageEditor), findsNothing);
      expect(find.text('Photo updated.'), findsOneWidget);
      final updated = await tester.runAsync(repository.list);
      expect(updated, hasLength(1));
      expect(updated!.single.thumbnail, isNot(orderedEquals(pixel)));
      expect(updated.single.reading, '12.50');
    },
  );
  testWidgets('ambiguous OCR requires correction; duplicate save prevented', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = ControlledRepository()..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewScreen(
          capture: fixture(),
          repository: repository,
          ocr: FakeOcr('12.5 34'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Confirm & save');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '12.50');
    await tester.pump();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(repository.confirmed, '12.50');
    expect(repository.writes, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
          .onPressed,
      isNull,
    );
    repository.pending!.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('failed save retains preview and permits retry', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = ControlledRepository()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewScreen(
          capture: fixture(),
          repository: repository,
          ocr: FakeOcr('12.5'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Confirm & save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Save failed.'), findsOneWidget);
    expect(find.byType(PhotoViews), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('VIEWFINDER CROP'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12.5',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm & save'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
