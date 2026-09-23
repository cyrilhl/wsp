import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as material_ui;
import 'package:pro_image_editor/pro_image_editor.dart';

import 'main.dart' show PhotoViews;
import 'services/images.dart';
import 'services/photos.dart';

class SavedPhotoScreen extends StatefulWidget {
  const SavedPhotoScreen({
    super.key,
    required this.photo,
    required this.repository,
  });

  final SavedPhoto photo;
  final PhotoRepository repository;

  @override
  State<SavedPhotoScreen> createState() => _SavedPhotoScreenState();
}

class _SavedPhotoScreenState extends State<SavedPhotoScreen> {
  late Uint8List _bytes = widget.photo.photo;

  Future<void> _edit() async {
    Uint8List? savedBytes;
    bool saveFailed = false;
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (editorContext) => Localizations.override(
          context: editorContext,
          delegates: material_ui.GlobalMaterialLocalizations.delegates,
          child: ProImageEditor.memory(
            _bytes,
            configs: const ProImageEditorConfigs(
              mainEditor: MainEditorConfigs(
                tools: [
                  SubEditorMode.paint,
                  SubEditorMode.text,
                  SubEditorMode.cropRotate,
                  SubEditorMode.tune,
                ],
              ),
            ),
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (bytes) async {
                try {
                  final prepared = await ImageService().prepare(bytes);
                  await widget.repository.updateImage(
                    widget.photo.id,
                    prepared.photo,
                    prepared.thumbnail,
                  );
                  savedBytes = prepared.photo;
                } catch (_) {
                  saveFailed = true;
                }
              },
              onCloseEditor: (_) {
                if (!editorContext.mounted) return;
                if (saveFailed) {
                  saveFailed = false;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!editorContext.mounted) return;
                    showDialog<void>(
                      context: editorContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Save failed'),
                        content: const Text(
                          'Your edits are still here. Please try again.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  });
                  return;
                }
                Navigator.pop(editorContext, savedBytes);
              },
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _bytes = result);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Photo updated.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Reading ${widget.photo.reading}'),
      actions: [
        IconButton(
          tooltip: 'Edit photo',
          onPressed: _edit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            PhotoViews(photo: _bytes),
            const SizedBox(height: 20),
            Text(
              widget.photo.reading,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            Text(widget.photo.capturedAt.toLocal().toString()),
          ],
        ),
      ),
    ),
  );
}
