import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OCRIsolateData {
  final CameraDescription camera;
  final CameraImage image;
  final SendPort sendPort;
  final RootIsolateToken token;
  final int sensorOrientation;
  OCRIsolateData(
    this.image,
    this.sendPort,
    this.token,
    this.sensorOrientation,
    this.camera,
  );
}

void ocrIsolate(OCRIsolateData data) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(data.token);
  final image = data.image;

  try {
    final filePath = await _saveCameraImageToFile(image, data.camera);
    data.sendPort.send(filePath);
  } catch (e) {
    data.sendPort.send("ERROR: $e");
  }
}

Future<String> _saveCameraImageToFile(
  CameraImage image,
  CameraDescription camera,
) async {
  final width = image.width;
  final height = image.height;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel!;

  final fullImage = img.Image(width: width, height: height);

  int rotationAngle = 0;
  switch (camera.sensorOrientation) {
    case 90:
      rotationAngle = -90;
      break;
    case 180:
      rotationAngle = 180;
      break;
    case 270:
      rotationAngle = 90;
      break;
    case 0:
    default:
      rotationAngle = 0;
      break;
  }

  // Step 1: Convert YUV to RGB (full image)
  for (int y = 0; y < height; y++) {
    final yRow = y * yPlane.bytesPerRow;

    for (int x = 0; x < width; x++) {
      final yPixel = yPlane.bytes[yRow + x];

      final uvX = x ~/ 2;
      final uvY = y ~/ 2;
      final uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

      final u = uPlane.bytes[uvIndex];
      final v = vPlane.bytes[uvIndex];

      final yVal = yPixel.toDouble();
      final uVal = u.toDouble() - 128.0;
      final vVal = v.toDouble() - 128.0;

      final r = (yVal + 1.402 * vVal).clamp(0, 255).toInt();
      final g =
          (yVal - 0.344136 * uVal - 0.714136 * vVal).clamp(0, 255).toInt();
      final b = (yVal + 1.772 * uVal).clamp(0, 255).toInt();

      fullImage.setPixelRgb(x, y, r, g, b);
    }
  }

  final rotated = img.copyRotate(fullImage, angle: rotationAngle);

  // Step 4: Encode and save
  final directory = await getTemporaryDirectory();
  final filePath =
      '${directory.path}/frame_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final jpegBytes = img.encodeJpg(rotated);
  final file = File(filePath);
  await file.writeAsBytes(jpegBytes);

  return filePath;
}
