import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation;

import 'saved_photo_screen.dart';
import 'services/images.dart';
import 'services/ocr.dart';
import 'services/photos.dart';
import 'services/platform.dart';
import 'services/reading.dart';

void main() =>
    runApp(MeterApp(repository: PhotoRepository(browserDatabaseFactory())));

class MeterApp extends StatelessWidget {
  const MeterApp({super.key, required this.repository});
  final PhotoRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fieldnote · Moisture meter',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176759)),
      scaffoldBackgroundColor: const Color(0xfff5f6f0),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff5f6f0)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
    ),
    home: HomeScreen(repository: repository),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});
  final PhotoRepository repository;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  String _offline = '';
  @override
  void initState() {
    super.initState();
    _offline = offlineStatus();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      final value = offlineStatus();
      if (mounted && value != _offline) setState(() => _offline = value);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('FIELDNOTE'),
      actions: const [
        Padding(padding: EdgeInsets.all(16), child: Text('MOISTURE STUDY')),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(28),
          children: [
            const Icon(
              Icons.water_drop_outlined,
              size: 58,
              color: Color(0xff176759),
            ),
            const SizedBox(height: 24),
            Text(
              'A clear record.\nOne reading at a time.',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 18),
            const Text(
              'Frame the meter display, check the reading, and keep the photo with its reading.',
              style: TextStyle(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take photo'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CameraScreen(repository: widget.repository),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              icon: const Icon(Icons.grid_view),
              label: const Text('View gallery'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => GalleryScreen(repository: widget.repository),
                ),
              ),
            ),
            const SizedBox(height: 36),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.offline_pin_outlined),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_offline)),
                      ],
                    ),
                    if (_offline.contains('failed'))
                      TextButton(
                        onPressed: retryOffline,
                        child: const Text('Retry offline setup'),
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      'Photos stay in this browser. Clearing site data removes your saved records.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.repository});
  final PhotoRepository repository;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  Size? _viewportSize;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    setState(() => _error = null);
    CameraController? next;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera found. Connect a camera and retry.');
      }
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      next = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      setState(() => _camera = next);
    } catch (error) {
      await next?.dispose();
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Could not open camera. Allow camera access and use HTTPS or localhost.\n$error',
        );
      }
    }
  }

  Future<void> _release() async {
    ++_generation;
    final old = _camera;
    _camera = null;
    await old?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_busy) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_release());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _initialize();
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    final viewportSize = _viewportSize;
    setState(() => _busy = true);
    try {
      final file = await camera.takePicture();
      final mirrored =
          camera.description.lensDirection != CameraLensDirection.back;
      final bytes = await file.readAsBytes();
      revokeCaptureUrl(file.path);
      final capture = await ImageService().prepare(
        bytes,
        mirrored: mirrored,
        viewportSize: viewportSize,
      );
      await _release();
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            capture: capture,
            repository: widget.repository,
            ocr: OcrService(),
          ),
        ),
      );
      if (!mounted) return;
      if (saved == true) {
        Navigator.pop(context);
        return;
      }
      await _initialize();
    } catch (error) {
      if (mounted) {
        await _release();
        if (mounted) {
          setState(() => _error = 'Capture failed. Please retry.\n$error');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        final camera = _camera;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              Center(
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  child: ErrorPanel(message: _error!, retry: _initialize),
                ),
              )
            else if (camera == null)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else ...[
              ValueListenableBuilder<CameraValue>(
                valueListenable: camera,
                builder: (context, value, _) {
                  final orientation =
                      value.previewPauseOrientation ??
                      value.lockedCaptureOrientation ??
                      value.deviceOrientation;
                  final portrait =
                      orientation == DeviceOrientation.portraitUp ||
                      orientation == DeviceOrientation.portraitDown;
                  final size = value.previewSize!;
                  final previewSize = !kIsWeb && portrait
                      ? Size(size.height, size.width)
                      : size;
                  return ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox.fromSize(
                        size: previewSize,
                        child: kIsWeb
                            ? camera.buildPreview()
                            : CameraPreview(camera),
                      ),
                    ),
                  );
                },
              ),
              const IgnorePointer(
                child: CustomPaint(painter: ViewfinderPainter()),
              ),
            ],
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Back',
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Frame the display',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_error == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Column(
                        children: [
                          const Text(
                            'Keep one reading inside the rectangle.\nAvoid glare and hold steady.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Semantics(
                            label: _busy ? 'Preparing photo' : 'Capture photo',
                            button: true,
                            child: SizedBox.square(
                              dimension: 80,
                              child: IconButton.filled(
                                tooltip: 'Capture photo',
                                onPressed: _busy || camera == null
                                    ? null
                                    : _capture,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.white38,
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                ),
                                icon: _busy
                                    ? const CircularProgressIndicator(
                                        color: Colors.black,
                                      )
                                    : const Icon(
                                        Icons.camera_alt_outlined,
                                        size: 32,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ViewfinderPainter extends CustomPainter {
  const ViewfinderPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = viewfinderFor(size);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .5));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(ViewfinderPainter oldDelegate) => false;
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.capture,
    required this.repository,
    required this.ocr,
  });
  final Capture capture;
  final PhotoRepository repository;
  final OcrService ocr;
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final _reading = TextEditingController();
  String _raw = '', _message = '';
  bool _processing = false, _saving = false, _saved = false;
  int? _ms;
  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    setState(() {
      _processing = true;
      _message = '';
      _raw = '';
      _ms = null;
    });
    try {
      final result = await widget.ocr.recognize(
        widget.capture.crop,
        enhanced: true,
      );
      if (!mounted) return;
      setState(() {
        _raw = result.rawText;
        _ms = result.elapsedMs;
        final value = parseReading(_raw);
        _reading.text = value ?? '';
        _message = value == null
            ? 'No single clear number found. Enter the reading or retake.'
            : 'Check every digit and the decimal point before saving.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'Recognition failed. Retry or enter the reading manually.\n$error',
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _save() async {
    if (_saved ||
        _saving ||
        _processing ||
        parseReading(_reading.text) == null) {
      return;
    }
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      await widget.repository.save(
        widget.capture,
        _reading.text,
        _raw,
        _ms,
        true,
      );
      _saved = true;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'Save failed. Your preview is still here; retry when storage is available.\n$error',
        );
      }
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving || _saved,
    child: Scaffold(
      appBar: AppBar(title: const Text('Check your reading')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PhotoViews(photo: widget.capture.photo),
              const SizedBox(height: 20),
              TextField(
                controller: _reading,
                enabled: !_processing && !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Confirmed reading',
                  hintText: 'e.g. 12.5',
                  helperText: 'One number, using a dot for decimals',
                ),
              ),
              const SizedBox(height: 16),
              if (_processing) const LinearProgressIndicator(),
              Text(_processing ? 'Reading the viewfinder crop…' : _message),
              if (_ms != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'OCR: ${(_ms! / 1000).toStringAsFixed(2)} s · Raw result: ${_raw.trim().isEmpty ? '(empty)' : _raw.trim()}',
                  ),
                ),
              TextButton.icon(
                onPressed: _processing || _saving ? null : _recognize,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry recognition'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    _processing ||
                        _saving ||
                        parseReading(_reading.text) == null
                    ? null
                    : _save,
                icon: const Icon(Icons.check),
                label: Text(_saving ? 'Saving…' : 'Confirm & save'),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Retake photo'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PhotoViews extends StatelessWidget {
  const PhotoViews({super.key, required this.photo});
  final Uint8List photo;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: double.infinity,
      height: 280,
      child: ColoredBox(
        color: const Color(0xff142d29),
        child: Image.memory(photo, fit: BoxFit.contain),
      ),
    ),
  );
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.repository});
  final PhotoRepository repository;
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Future<List<SavedPhoto>> _photos;
  late Future<double?> _storageUsage;
  @override
  void initState() {
    super.initState();
    _photos = widget.repository.list();
    _storageUsage = browserStorageUsage();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your gallery'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          child: FutureBuilder<double?>(
            future: _storageUsage,
            builder: (context, snapshot) {
              final loading = snapshot.connectionState != ConnectionState.done;
              final usage = loading ? null : snapshot.data;
              final percentage = usage == null ? null : usage * 100;
              final label = loading
                  ? 'Checking browser storage…'
                  : percentage == null
                  ? 'Storage estimate unavailable'
                  : 'Browser storage: ${percentage > 0 && percentage < 0.1 ? '<0.1' : percentage.toStringAsFixed(1)}% used';
              return Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: 'Estimated usage of this site’s browser storage allowance, including photos and offline caches.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label),
                          if (usage != null) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: usage,
                              semanticsLabel: label,
                              color: usage >= 0.8
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh storage usage',
                    onPressed: loading
                        ? null
                        : () => setState(() {
                            _storageUsage = browserStorageUsage();
                          }),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    body: FutureBuilder<List<SavedPhoto>>(
      future: _photos,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(
            message: 'Could not load saved photos.\n${snapshot.error}',
            retry: () => setState(() {
              _photos = widget.repository.list();
              _storageUsage = browserStorageUsage();
            }),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final photos = snapshot.data!;
        if (photos.isEmpty) {
          return const Center(
            child: Text('No photos yet. Take your first reading.'),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: photos.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .9,
          ),
          itemBuilder: (context, index) {
            final photo = photos[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SavedPhotoScreen(
                        photo: photo,
                        repository: widget.repository,
                      ),
                    ),
                  );
                  if (mounted) {
                    setState(() {
                      _photos = widget.repository.list();
                      _storageUsage = browserStorageUsage();
                    });
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Image.memory(photo.thumbnail, fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            photo.reading,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            photo.capturedAt
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 16),
          FilledButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
