import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'services/minibike_ble.dart';

class TestsScreen extends StatelessWidget {
  const TestsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tests')),
        body: ListView(children: [
          ListTile(
            leading: const Icon(Icons.lightbulb),
            title: const Text('Lighting Test'),
            subtitle: const Text('UART RX/TX, lock, light and brake markers'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LightingTestScreen()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.folder),
            title: Text('Recordings'),
            subtitle: Text('Saved files are available from Lighting Test'),
          ),
          const ListTile(
            enabled: false,
            leading: Icon(Icons.speed),
            title: Text('Speed & Motor Test (later)'),
          ),
          const ListTile(
            enabled: false,
            leading: Icon(Icons.battery_full),
            title: Text('Battery Test (later)'),
          ),
        ]),
      );
}

class LightingTestScreen extends StatefulWidget {
  const LightingTestScreen({super.key});

  @override
  State<LightingTestScreen> createState() => _LightingTestScreenState();
}

class _LightingTestScreenState extends State<LightingTestScreen> {
  bool recording = false;
  bool busy = false;
  File? currentFile;
  IOSink? sink;
  StreamSubscription<List<int>>? subscription;
  int rx = 0;
  int tx = 0;
  int bad = 0;
  String message = 'Ready';
  List<File> files = [];
  final Stopwatch watch = Stopwatch();

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  Future<Directory> folder() async {
    final d = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/es200_tests',
    );
    await d.create(recursive: true);
    return d;
  }

  Future<void> loadFiles() async {
    final d = await folder();
    final all = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.csv'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (mounted) setState(() => files = all);
  }

  void event(String name) {
    if (!recording) return;
    sink?.writeln(
      '${DateTime.now().toUtc().toIso8601String()},'
      '${watch.elapsedMilliseconds},EVENT,$name',
    );
  }

  Future<void> start(MiniBikeBle ble) async {
    if (!ble.isConnected || !ble.supportsLogger) {
      throw Exception('Connect ESP32 firmware v07 first');
    }
    final d = await folder();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final f = File('${d.path}/ES200_Lighting_$stamp.csv');
    final out = f.openWrite();
    out.writeln('phone_utc,esp_ms,direction,hex_or_event');
    rx = 0;
    tx = 0;
    bad = 0;
    currentFile = f;
    sink = out;
    watch.reset();
    watch.start();

    subscription = ble.logRecords.listen((data) {
      if (data.length < 5) {
        bad++;
        return;
      }
      final type = data[0];
      final ms = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
      final hex = data
          .skip(5)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      out.writeln(
        '${DateTime.now().toUtc().toIso8601String()},$ms,'
        '${type == 1 ? 'RX' : type == 2 ? 'TX' : 'UNKNOWN'},"$hex"',
      );
      if (type == 1) {
        rx++;
      } else if (type == 2) {
        tx++;
      } else {
        bad++;
      }
      if (mounted && (rx + tx) % 10 == 0) setState(() {});
    });

    try {
      await ble.startLogging();
    } catch (_) {
      await subscription?.cancel();
      subscription = null;
      watch.stop();
      await out.close();
      sink = null;
      rethrow;
    }
    if (mounted) {
      setState(() {
        recording = true;
        message = 'Recording';
      });
    }
    event('START_LIGHTING_TEST');
  }

  Future<void> stop(MiniBikeBle ble) async {
    event('STOP_LIGHTING_TEST');
    try {
      if (ble.isConnected) await ble.stopLogging();
    } catch (_) {
      // Keep the local CSV even if BLE was disconnected.
    }
    await subscription?.cancel();
    subscription = null;
    watch.stop();
    await sink?.flush();
    await sink?.close();
    sink = null;
    if (mounted) {
      setState(() {
        recording = false;
        message = 'Saved ${currentFile?.path.split('/').last}';
      });
    }
    await loadFiles();
  }

  Future<void> share(File f) async => Share.shareXFiles(
        [XFile(f.path)],
        text: 'ES200 lighting test UART log',
      );

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmExit() async {
    if (busy) return;
    if (!recording) {
      Navigator.of(context).pop();
      return;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recording in progress'),
        content: const Text('Stop recording, save CSV and leave Lighting Test?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue recording'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop and exit'),
          ),
        ],
      ),
    );
    if (shouldExit != true || !mounted) return;
    await run(() => stop(context.read<MiniBikeBle>()));
    if (mounted && !recording) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // A route exit is guarded by PopScope. If Android kills the process,
    // the recording cannot be guaranteed to be finalized.
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<MiniBikeBle>();
    final connected = ble.isConnected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lighting Test'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: busy ? null : confirmExit,
          ),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(message),
          Text('RX $rx   TX $tx   Invalid $bad'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: connected && !busy
                ? () => run(() => recording ? stop(ble) : start(ble))
                : null,
            icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(recording ? 'Stop recording' : 'Start recording'),
          ),
          const SizedBox(height: 16),
          const Text('Test actions', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: connected && !busy
                ? () => run(() async {
                      final unlock = ble.unlocked != true;
                      if (unlock) {
                        await ble.unlockScooter();
                      } else {
                        await ble.lockScooter();
                      }
                      event(unlock ? 'UNLOCK_COMMAND_SENT' : 'LOCK_COMMAND_SENT');
                    })
                : null,
            icon: Icon(ble.unlocked == true ? Icons.lock : Icons.lock_open),
            label: Text(ble.unlocked == true ? 'LOCK' : 'UNLOCK'),
          ),
          OutlinedButton.icon(
            onPressed: connected && !busy
                ? () => run(() async {
                      await ble.toggleScooterLight();
                      event('LIGHT_TOGGLE_COMMAND_SENT');
                    })
                : null,
            icon: const Icon(Icons.lightbulb),
            label: Text(
              'Toggle front light '
              '(${ble.lightOn == null ? '?' : ble.lightOn! ? 'ON' : 'OFF'})',
            ),
          ),
          OutlinedButton.icon(
            onPressed: recording && !busy
                ? () => event('BRAKE_PRESSED_MANUAL_MARKER')
                : null,
            icon: const Icon(Icons.pan_tool),
            label: const Text('Brake marker'),
          ),
          const SizedBox(height: 8),
          const Text(
            'LOCK/UNLOCK and light status are last commanded states, '
            'not independently verified ECU feedback.',
            style: TextStyle(fontSize: 12),
          ),
          const Divider(),
          const Text('Saved recordings', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final f in files)
            ListTile(
              title: Text(
                f.path.split('/').last,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.share),
                onPressed: busy ? null : () => run(() => share(f)),
              ),
            ),
          const Text(
            'Test only while stationary. Do not operate the phone while riding.',
            style: TextStyle(fontSize: 12),
          ),
        ]),
      ),
    );
  }
}
