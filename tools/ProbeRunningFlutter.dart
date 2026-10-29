import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

// Developer-only probe using the SDK's VM client. Never reads or prints credentials.
// Args: private flutter run log, optional expression-file executed on the app state.
Future<void> main(List<String> args) async {
  VmService? service;
  var stage = 'read-log';
  try {
    final bytes = File(args.first).readAsBytesSync();
    final log = bytes.length > 1 && bytes[0] == 255 && bytes[1] == 254
        ? String.fromCharCodes([
            for (var i = 2; i + 1 < bytes.length; i += 2)
              bytes[i] | (bytes[i + 1] << 8),
          ])
        : utf8.decode(bytes);
    final match = RegExp(
      r'A Dart VM Service on .*? is available at: (http://127\.0\.0\.1:\d+/[^\s]+)',
    ).firstMatch(log);
    if (match == null) throw StateError('VM service is not ready');
    final endpoint = Uri.parse(
      match.group(1)!.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), ''),
    );
    final ws = endpoint.replace(scheme: 'ws', path: '${endpoint.path}ws');
    stage = 'connect-local-debugger';
    service = await vmServiceConnectUri(ws.toString());
    final vm = await service.getVM();
    final isolateRef = vm.isolates!.firstWhere((i) => i.name == 'main');
    final isolateId = isolateRef.id!;
    final isolate = await service.getIsolate(isolateId);
    stage = 'read-app-metadata';
    final library =
        await service.getObject(isolateId, isolate.rootLib!.id!) as Library;
    final stateClass = library.classes!.firstWhere(
      (c) => c.name == '_NhomBarAppState',
    );
    final instances = await service.getInstances(isolateId, stateClass.id!, 1);
    final stateId = instances.instances!.single.id!;
    final url = await service.evaluate(
      isolateId,
      stateId,
      'api.dio.options.baseUrl',
    );
    if (url is InstanceRef) stdout.writeln('API_BASE_URL=${url.valueAsString}');
    final expression = args.length > 1
        ? File(args[1]).readAsStringSync()
        : r'''(() async {
      try {
        final h = await api.dio.get('/health');
        final u = await api.dio.get('/api/users/me');
        return 'HEALTH=' + h.statusCode.toString() + ';AUTH=' + u.statusCode.toString() + ';ROLE=' + u.data['role'].toString();
      } catch (e) { return 'PROBE_ERROR=' + e.runtimeType.toString(); }
    })()''';
    stage = 'run-http-probe';
    final evaluated = await service.evaluate(
      isolateId,
      stateId,
      expression.replaceAll('\r', ' ').replaceAll('\n', ' '),
    );
    if (evaluated is! InstanceRef) throw StateError('Evaluation failed');
    if (evaluated.kind == InstanceKind.kString) {
      stdout.writeln(evaluated.valueAsString);
      return;
    }
    for (var n = 0; n < 90; n++) {
      final future =
          await service.getObject(isolateId, evaluated.id!) as Instance;
      final result = future.fields
          ?.where((f) => f.decl?.name == '_resultOrListeners')
          .firstOrNull
          ?.value;
      if (result is InstanceRef && result.kind == InstanceKind.kString) {
        stdout.writeln(result.valueAsString);
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException('Probe did not complete');
  } catch (e) {
    stderr.writeln(
      'Probe unavailable: ${e.runtimeType}; stage=$stage${e is FileSystemException ? '; ioCode=${e.osError?.errorCode}' : ''}. No credentials were printed.',
    );
    if (e is RPCError) stderr.writeln('RPC code=${e.code}; ${e.details}');
    exitCode = 1;
  } finally {
    await service?.dispose();
  }
}
