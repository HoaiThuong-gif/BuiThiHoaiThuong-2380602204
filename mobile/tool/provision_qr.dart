import 'dart:io';

import 'package:qr/qr.dart';

// Offline renderer: no provisioning or device access occurs here.
void main(List<String> args) {
  if (args.length != 2) throw ArgumentError('payload.json output.svg');
  final image = QrImage(
    QrCode.fromData(
      data: File(args[0]).readAsStringSync(),
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ),
  );
  final size = image.moduleCount + 8;
  final svg = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="720" height="720" shape-rendering="crispEdges"><rect width="$size" height="$size" fill="white"/><g fill="black">',
  );
  for (var row = 0; row < image.moduleCount; row++) {
    for (var col = 0; col < image.moduleCount; col++) {
      if (image.isDark(row, col)) {
        svg.write('<rect x="${col + 4}" y="${row + 4}" width="1" height="1"/>');
      }
    }
  }
  File(args[1]).writeAsStringSync('$svg</g></svg>');
  stdout.writeln('QR file generated offline. No device was configured.');
}
