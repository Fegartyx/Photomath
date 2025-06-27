import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class InitCamera extends StatefulWidget {
  const InitCamera({super.key});

  @override
  State<InitCamera> createState() => _InitCameraState();
}

class _InitCameraState extends State<InitCamera> {
  late List<CameraDescription> cameras;
  CameraController? controller;
  final RootIsolateToken _rootIsolateToken = RootIsolateToken.instance!;
  int sensorOrientation = 0;
  bool _isStreaming = false;
  late TextRecognizer _textRecognizer;
  String _recognizedText = '';

  Future<void> _initializeCamera() async {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    cameras = await availableCameras();
    controller = CameraController(
      cameras[0],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid
              ? ImageFormatGroup
                  .nv21 // for Android
              : ImageFormatGroup.bgra8888, // for iOS
    );
    await controller!.initialize();
    sensorOrientation = cameras[0].sensorOrientation;
    setState(() {});
  }

  Future analyzeImage(img.Image image) async {
    try {
      // TODO: Call HTTP API or perform OCR here
      final jpegBytes = img.encodeJpg(image);
    } catch (e) {
      print("❌ Error analyzing image: $e");
      rethrow;
    }
  }

  bool isInsideBox(Rect textBox, Size imageSize, Size screenSize) {
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Ukuran dan posisi box (sesuaikan dengan UI kotak putih)
    final boxWidth = 250.0;
    final boxHeight = 100.0;
    final boxLeft = (screenWidth - boxWidth) / 2;
    final boxTop = (screenHeight - boxHeight) / 2;

    final boxRect = Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight);

    // Skala konversi koordinat image ke layar
    final scaleX = screenWidth / imageSize.width;
    final scaleY = screenHeight / imageSize.height;

    final adjustedTextRect = Rect.fromLTWH(
      textBox.left * scaleX,
      textBox.top * scaleY,
      textBox.width * scaleX,
      textBox.height * scaleY,
    );

    return boxRect.overlaps(adjustedTextRect);
  }

  void _startImageStream() {
    if (!_isStreaming) {
      _isStreaming = true;

      controller!.startImageStream((CameraImage image) async {
        try {
          final file = await controller!.takePicture();
          final inputImage = InputImage.fromFilePath(file.path);

          final recognisedText = await _textRecognizer.processImage(inputImage);

          final imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );

          final screenSize = MediaQuery.of(context).size;

          final filteredText = recognisedText.blocks
              .where(
                (block) =>
                    block.boundingBox != null &&
                    isInsideBox(block.boundingBox!, imageSize, screenSize),
              )
              .map((e) => e.text)
              .join('\n');

          setState(() {
            _recognizedText = filteredText;
          });
        } catch (e) {
          print("OCR error: $e");
        }

        // try {
        //   final imgExtract = img.Image(
        //     width: image.width,
        //     height: image.height,
        //   );
        //   await analyzeImage(imgExtract);
        // } catch (e) {
        //   print("❌ Error processing image: $e");
        //   rethrow;
        // }

        // final receivePort = ReceivePort();
        // await Isolate.spawn(
        //   ocrIsolate,
        //   OCRIsolateData(
        //     image,
        //     receivePort.sendPort,
        //     _rootIsolateToken,
        //     sensorOrientation,
        //     cameras[0],
        //   ),
        // );

        // final filePath = await receivePort.first as String;
        //
        // if (filePath is String && !filePath.startsWith("ERROR")) {
        //   final inputImage = InputImage.fromFilePath(filePath);
        //   final textRecognizer = TextRecognizer();
        //   final visionText = await textRecognizer.processImage(inputImage);
        //   await textRecognizer.close();
        //   // await File(filePath).delete();
        //
        //   print("✅ OCR Success: ${visionText.text}");
        // } else {
        //   print("❌ OCR Failed: $filePath");
        // }
      });
    }
  }

  Future<void> _takePictureAndRecognizeText() async {
    try {
      final file = await controller!.takePicture();
      final imageSize = await compute(getImageSizeFromFile, file.path);

      final inputImage = InputImage.fromFilePath(file.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final screenSize = MediaQuery.of(context).size;

      final filteredText = recognizedText.blocks
          .where(
            (block) =>
                block.boundingBox != null &&
                isInsideBox(block.boundingBox, imageSize, screenSize),
          )
          .map((e) => e.text)
          .join('\n');

      setState(() {
        _recognizedText = filteredText;
      });
      debugPrint("Recognized Text: $_recognizedText");
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    if (_isStreaming) {
      controller!.stopImageStream();
    }
    controller!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(controller!)),
        // Lapisan blur di atas semua
        // Positioned.fill(
        //   child: Blur(
        //     blur: 5,
        //     blurColor: Colors.transparent,
        //     child: Container(),
        //   ),
        // ),

        // Area fokus (non-blur)
        Center(
          child: Container(
            width: 250,
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(25),
            ),
            // area ini akan tetap jernih karena berada di atas layer blur
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: GestureDetector(
                  onTap: () {
                    _takePictureAndRecognizeText();
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Size getImageSizeFromFile(String path) {
  final bytes = File(path).readAsBytesSync();
  final decodedImage = img.decodeImage(bytes);
  if (decodedImage != null) {
    return Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
  } else {
    throw Exception("Unable to decode image");
  }
}
