import 'dart:io';

import 'package:qr/qr.dart';

void main(List<String> args) {
  final code = QrImage(
    QrCode.fromData(
      data: 'NHOMBAR-USB-TEST-20261029',
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ),
  );
  final size = code.moduleCount + 8;
  final svg = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="600" height="600"><rect width="$size" height="$size" fill="white"/><g fill="black">',
  );
  for (var y = 0; y < code.moduleCount; y++) {
    for (var x = 0; x < code.moduleCount; x++) {
      if (code.isDark(y, x)) {
        svg.write('<rect x="${x + 4}" y="${y + 4}" width="1" height="1"/>');
      }
    }
  }
  svg.write('</g></svg>');
  final file = File(args.isEmpty ? 'build/usb-test/qr-check.svg' : args.first);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(svg.toString());
  stdout.writeln('Public camera test QR generated: ${file.path}');
}
