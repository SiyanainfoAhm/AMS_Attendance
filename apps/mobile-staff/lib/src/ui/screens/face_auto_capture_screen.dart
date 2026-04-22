import "dart:async";
import "dart:typed_data";

import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "package:google_mlkit_face_detection/google_mlkit_face_detection.dart";

import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";

class FaceAutoCaptureResult {
  final Uint8List bytes;
  FaceAutoCaptureResult({required this.bytes});
}

class FaceAutoCaptureScreen extends StatefulWidget {
  const FaceAutoCaptureScreen({super.key});

  @override
  State<FaceAutoCaptureScreen> createState() => _FaceAutoCaptureScreenState();
}

class _FaceAutoCaptureScreenState extends State<FaceAutoCaptureScreen> {
  CameraController? _cam;
  FaceDetector? _detector;

  bool _starting = true;
  bool _processing = false;
  bool _capturing = false;

  String _hint = "Align your face in the frame";
  bool _faceOk = false;

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<CameraImage>? _streamSub;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_streamSub?.cancel());
    unawaited(_cam?.stopImageStream());
    unawaited(_cam?.dispose());
    unawaited(_detector?.close());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      final front = cams.where((c) => c.lensDirection == CameraLensDirection.front).toList();
      final camDesc = front.isNotEmpty ? front.first : cams.first;

      final detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: false,
          enableContours: false,
          enableClassification: false,
          enableTracking: true,
          minFaceSize: 0.18,
        ),
      );
      final ctrl = CameraController(
        camDesc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();

      if (!mounted) {
        await ctrl.dispose();
        await detector.close();
        return;
      }

      setState(() {
        _cam = ctrl;
        _detector = detector;
        _starting = false;
      });

      await ctrl.startImageStream(_onFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _hint = "Camera unavailable: $e";
      });
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    if (!mounted) return;
    if (_capturing) return;
    if (_processing) return;

    // Throttle: process at most ~5 fps.
    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < 180) return;
    _lastProcessed = now;

    final cam = _cam;
    final detector = _detector;
    if (cam == null || detector == null) return;

    _processing = true;
    try {
      final input = _cameraImageToInputImage(img, cam.description.sensorOrientation);
      final faces = await detector.processImage(input);

      // Be tolerant for reliability across devices: require exactly one face.
      // (We can tighten this later with size/center constraints once stable everywhere.)
      final ok = faces.length == 1;
      _setFaceOk(ok);
      _setHint(ok ? "Face detected. Tap Capture." : _hintForFaces(faces));
    } catch (_) {
      _setFaceOk(false);
    } finally {
      _processing = false;
    }
  }

  void _setHint(String msg) {
    if (!mounted) return;
    if (_hint == msg) return;
    setState(() => _hint = msg);
  }

  void _setFaceOk(bool ok) {
    if (!mounted) return;
    if (_faceOk == ok) return;
    setState(() => _faceOk = ok);
  }

  String _hintForFaces(List<Face> faces) {
    if (faces.isEmpty) return "No face detected. Look at the camera.";
    if (faces.length > 1) return "Only one face allowed.";
    return "Center your face and move closer.";
  }

  Future<void> _capture() async {
    final cam = _cam;
    final detector = _detector;
    if (cam == null || detector == null) return;
    if (_capturing) return;
    _capturing = true;
    _setHint("Capturing…");

    try {
      // Stop stream before taking picture (required on many devices).
      await cam.stopImageStream();
      final file = await cam.takePicture();
      // Validate face on the captured image (more reliable than stream-based gating).
      final input = InputImage.fromFilePath(file.path);
      final faces = await detector.processImage(input);
      if (faces.length != 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(faces.isEmpty ? "No face detected. Please retake." : "Multiple faces detected. Please retake."),
          ),
        );
        _setHint(faces.isEmpty ? "No face detected. Retake." : "Only one face allowed. Retake.");
        _setFaceOk(false);
        _capturing = false;
        try {
          await cam.startImageStream(_onFrame);
        } catch (_) {}
        return;
      }

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(FaceAutoCaptureResult(bytes: bytes));
    } catch (e) {
      if (!mounted) return;
      _setHint("Capture failed. Try again. ($e)");
      _capturing = false;
      try {
        await cam.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  InputImage _cameraImageToInputImage(CameraImage image, int sensorOrientation) {
    final bb = BytesBuilder(copy: false);
    for (final plane in image.planes) {
      bb.add(plane.bytes);
    }
    final bytes = bb.takeBytes();

    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;
    // google_mlkit_face_detection depends on google_mlkit_commons; metadata API can vary by version.
    // The current stable API uses InputImageMetadata without planeData.
    final metadata = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return AmsScaffold(
      title: "Face capture",
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Selfie", style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_hint, style: const TextStyle(color: AmsTokens.muted)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  color: Colors.black,
                  child: _starting
                      ? const Center(child: CircularProgressIndicator())
                      : cam == null
                          ? const Center(child: Text("Camera not available", style: TextStyle(color: Colors.white)))
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(cam),
                                IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      width: 220,
                                      height: 280,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: Colors.white.withOpacity(0.75), width: 2),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            AmsPrimaryButton(
              label: "Capture",
              icon: Icons.camera_alt_outlined,
              loading: _capturing,
              onPressed: (!_starting && cam != null && !_capturing)
                  ? () {
                      _capture();
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            AmsSecondaryButton(
              label: "Cancel",
              icon: Icons.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

