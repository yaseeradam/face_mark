import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageCompressor {
  static Future<File> compressForUpload(
    File input, {
    int maxDimension = 640,
    int quality = 80,
  }) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return input;

    final oriented = img.bakeOrientation(decoded);
    final resized = _resizeIfNeeded(oriented, maxDimension);
    final encoded = img.encodeJpg(resized, quality: quality);

    final dir = await getTemporaryDirectory();
    final outPath = p.join(
      dir.path,
      'upload_${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(input.path)}.jpg',
    );
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded, flush: true);
    return outFile;
  }

  static img.Image _resizeIfNeeded(img.Image image, int maxDimension) {
    final maxSide = image.width > image.height ? image.width : image.height;
    if (maxSide <= maxDimension) return image;

    final scale = maxDimension / maxSide;
    final newWidth = (image.width * scale).round().clamp(1, maxDimension);
    final newHeight = (image.height * scale).round().clamp(1, maxDimension);

    return img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );
  }
}
