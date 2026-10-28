import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:minibike_stats/models/telemetry_packet.dart';

/// BLE communication manager for MiniBike Stats
/// 
/// Connects to ESP32 advertising as "MiniBikeStats"
/// Subscribes to real-time telemetry notifications
class MiniBikeBle extends ChangeNotifier {
  static const String deviceName = "MiniBikeStats";

  // Same UUIDs as firmware
  static final Guid serviceUuid = Guid("a1b2c3d4-0000-0000-0000-00000000beef");
  static final Guid telemetryCharUuid = Guid("a1b2c3d4-1001-0000-0000-00000000beef");
  static final Guid commandCharUuid = Guid("a1b2c3d4-1002-0000-0000-00000000beef");

  static final Guid logCharUuid = Guid("a1b2c3d4-1003-0000-0000-00000000beef");
  static final Guid stateCharUuid = Guid("a1b2c3d4-1004-0000-0000-00000000beef");
  BluetoothCharacteristic? _logChar;
  BluetoothCharacteristic? _stateChar;
  StreamSubscription<List<int>>? _logSubscription;
  StreamSubscription<List<int>>? _stateSubscription;
  final StreamController<List<int>> _logs = StreamController<List<int>>.broadcast();
  Stream<List<int>> get logRecords => _logs.stream;
  bool? lightOn;
  bool? unlocked; // requested LOCK/UNLOCK, for compatibility with test screen
  bool? actualUnlocked;
  bool? brakeActive;
  bool supportsLogger = false;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _telemetryChar;
  BluetoothCharacteristic? _commandChar;

  StreamSubscription<List<int>>? _telemetrySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  TelemetryPacket? latestTelemetry;
  bool isConnected = false;
  bool isScanning = false;
  String statusMessage = "Disconnected";

  BluetoothDevice? get device => _device;

  /// Scan and connect to the MiniBike
  Future<void> connect() async {
    if (isConnected) return;

    try {
      statusMessage = "Checking Bluetooth permissions...";
      notifyListeners();

      if (await FlutterBluePlus.isSupported == false) {
        throw Exception("Bluetooth is not supported");
      }

      if (Platform.isAndroid) {
        final permissions = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
        debugPrint("BLE permissions: $permissions");
        if (permissions.values.any((status) => !status.isGranted)) {
          throw Exception("Nearby devices permission denied: $permissions");
        }
      }

      statusMessage = "Scanning for $deviceName...";
      isScanning = true;
      notifyListeners();

      final completer = Completer<BluetoothDevice?>();
      // Subscribe BEFORE starting the scan. Do not filter by advertising name
      // at the OS level: some ESP32 stacks put the name in scan response data.
      final sub = FlutterBluePlus.scanResults.listen((results) {
        if (completer.isCompleted) return;
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          debugPrint("BLE candidate: $name / ${r.device.remoteId}");
          if (name == deviceName || r.device.platformName == deviceName) {
            completer.complete(r.device);
            return;
          }
        }
      });

      BluetoothDevice? foundDevice;
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
        foundDevice = await completer.future.timeout(
          const Duration(seconds: 10), onTimeout: () => null);
      } finally {
        await FlutterBluePlus.stopScan();
        await sub.cancel();
      }
      if (foundDevice == null) {
        throw Exception("MiniBikeStats not found. Check ESP32 advertising.");
      }

      _device = foundDevice;
      statusMessage = "Connecting to ${_device!.platformName}...";
      notifyListeners();

      // Connect
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      // Listen for connection state changes
      _connectionSubscription = _device!.connectionState.listen((state) {
        isConnected = state == BluetoothConnectionState.connected;
        if (!isConnected) {
          _cleanupConnection();
        }
        statusMessage = isConnected ? "Connected" : "Disconnected";
        notifyListeners();
      });

      // Discover services
      await _device!.discoverServices();

      final services = _device!.servicesList;
      final service = services.firstWhere(
        (s) => s.uuid == serviceUuid,
        orElse: () => throw Exception("MiniBike service not found"),
      );

      // Find characteristics
      _telemetryChar = service.characteristics.firstWhere(
        (c) => c.uuid == telemetryCharUuid,
      );
      _commandChar = service.characteristics.firstWhere(
        (c) => c.uuid == commandCharUuid,
      );

      _logChar = service.characteristics.where((c) => c.uuid == logCharUuid).firstOrNull;
      _stateChar = service.characteristics.where((c) => c.uuid == stateCharUuid).firstOrNull;
      supportsLogger = _logChar != null && _stateChar != null;
      if (_logChar != null) {
        _logSubscription = _logChar!.onValueReceived.listen((v) { if (!_logs.isClosed) _logs.add(v); });
        await _logChar!.setNotifyValue(true);
      }
      if (_stateChar != null) {
        void updateState(List<int> v) {
          if (v.length >= 5 && v[0] == 2) {
            unlocked = v[1] != 0;
            actualUnlocked = v[2] == 2 ? null : v[2] == 1;
            lightOn = v[3] == 2 ? null : v[3] == 1;
            brakeActive = v[4] == 2 ? null : v[4] == 1;
            notifyListeners();
          } else if (v.length >= 3 && v[0] == 1) {
            // Older ESP firmware: light is only a requested state, not verified.
            unlocked = v[1] != 0;
            actualUnlocked = null;
            lightOn = null;
            brakeActive = null;
            notifyListeners();
          }
        }
        _stateSubscription = _stateChar!.onValueReceived.listen(updateState);
        await _stateChar!.setNotifyValue(true);
        updateState(await _stateChar!.read());
      }
      // Subscribe to telemetry notifications (real-time updates)
      if (_telemetryChar!.properties.notify) {
        await _telemetryChar!.setNotifyValue(true);

        _telemetrySubscription = _telemetryChar!.onValueReceived.listen((value) {
          try {
            final packet = TelemetryPacket.fromBytes(value);
            latestTelemetry = packet;
            statusMessage = "Receiving data";
            notifyListeners();
          } catch (e) {
            debugPrint("Failed to parse telemetry: $e");
          }
        }, onError: (e) {
          debugPrint("Telemetry stream error: $e");
        });
      }

      // Request a higher MTU for better performance (Android mostly)
      if (Platform.isAndroid) {
        await _device!.requestMtu(185);
      }

      isConnected = true;
      statusMessage = "Connected - receiving real-time stats";
      notifyListeners();

    } catch (e) {
      statusMessage = "Error: $e";
      debugPrint("BLE connect error: $e");
      await disconnect(shouldNotify: false);
      statusMessage = "Error: $e";
      notifyListeners();
      rethrow;
    } finally {
      isScanning = false;
      notifyListeners();
    }
  }

  /// Send a simple command byte to the ESP32
  Future<void> sendCommand(int commandByte) async {
    if (!isConnected || _commandChar == null) {
      throw Exception("Not connected");
    }

    try {
      await _commandChar!.write([commandByte], withoutResponse: true);
      debugPrint("Sent command: 0x${commandByte.toRadixString(16)}");
    } catch (e) {
      debugPrint("Failed to send command: $e");
      rethrow;
    }
  }

  /// Convenience methods for known commands (match firmware)
  Future<void> cycleDisplaySkin() async => sendCommand(0x01);
  Future<void> resetTrip() async => sendCommand(0x02);

  // ES200G prototype command extension (0x20-0x22)
  Future<void> lockScooter() async => sendCommand(0x20);
  Future<void> unlockScooter() async => sendCommand(0x21);
  Future<void> toggleScooterLight() async => sendCommand(0x22);

  Future<void> startLogging() async => sendCommand(0x30);
  Future<void> stopLogging() async => sendCommand(0x31);

  Future<void> disconnect({bool shouldNotify = true}) async {
    await _cleanupConnection();
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    isConnected = false;
    statusMessage = "Disconnected";
    if (shouldNotify) {
      notifyListeners();
    }
  }

  Future<void> _cleanupConnection() async {
    await _telemetrySubscription?.cancel();
    _telemetrySubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    await _logSubscription?.cancel(); _logSubscription = null;
    await _stateSubscription?.cancel(); _stateSubscription = null;
    _logChar = null; _stateChar = null; supportsLogger = false;
    lightOn = null; unlocked = null; actualUnlocked = null; brakeActive = null;
    _telemetryChar = null;
    _commandChar = null;

    latestTelemetry = null;
  }

  @override
  void dispose() {
    disconnect(shouldNotify: false);
    _logs.close();
    super.dispose();
  }
}
