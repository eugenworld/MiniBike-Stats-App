import 'package:flutter/material.dart';
import 'package:minibike_stats/services/minibike_ble.dart';
import 'package:provider/provider.dart';

void main() => runApp(ChangeNotifierProvider(
      create: (_) => MiniBikeBle(),
      child: const MiniBikeStatsApp(),
    ));

class MiniBikeStatsApp extends StatelessWidget {
  const MiniBikeStatsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MiniBike Stats',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const DashboardScreen(),
        debugShowCheckedModeBanner: false,
      );
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<MiniBikeBle>();
    final phase = ble.phase;
    final speed = ble.latestTelemetry?.speedKmh;
    final soc = ble.latestTelemetry?.soc;
    final ready = ble.isConnected && !ble.isScanning && phase != null;
    final canLock = ready && speed != null && speed.isFinite &&
        (phase == 0 && speed == 0 || phase == 4 && speed <= 2);
    final canUnlock = ready && phase == 2 && ble.actualUnlocked == false &&
        !ble.charging && speed == 0;
    final canUseLight = ready && phase == 4 && ble.actualUnlocked == true &&
        ble.lightOn != null;

    final status = switch (phase) {
      0 => 'Ожидание остановки и команды LOCK',
      1 => 'Блокировка…',
      2 when ble.actualUnlocked == false => 'LOCK',
      3 => 'Разблокировка…',
      4 when ble.actualUnlocked == true => 'UNLOCK',
      5 => 'Блокировка…',
      _ => '—',
    };
    final message = switch (ble.commandResult) {
      1 => 'Ожидание телеметрии.',
      2 => 'Остановите самокат.',
      3 => 'Разблокировка недоступна во время зарядки.',
      4 => 'Действие недоступно в текущем состоянии.',
      5 => 'Переподключите приложение для синхронизации времени.',
      _ => null,
    };

    Future<void> perform(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('MiniBike Stats')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(ble.statusMessage),
              trailing: FilledButton(
                onPressed: ble.isScanning
                    ? null
                    : () => perform(ble.isConnected ? ble.disconnect : ble.connect),
                child: Text(ble.isConnected ? 'Отключить' : 'Подключить'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: Text(ble.charging ? 'Зарядка' : 'Заряд аккумулятора'),
              subtitle: Text(soc != null && soc.isFinite
                  ? '${soc.toStringAsFixed(0)} %'
                  : '—'),
            ),
          ),
          if (ble.charging)
            ListTile(
              title: const Text('До полного заряда'),
              subtitle: Text(ble.chargingMinutes == null
                  ? 'Расчёт времени…'
                  : '≈ ${ble.chargingMinutes} мин'),
            ),
          ListTile(
            title: const Text('Общий пробег'),
            subtitle: Text(ble.odometerKm == null
                ? '—'
                : '≈ ${ble.odometerKm!.toStringAsFixed(1)} км · предварительно'),
          ),
          ListTile(title: Text(status)),
          if (phase == 0 && const [4, 5, 6, 7].contains(ble.resetReason))
            const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('ESP32 перезапустился после сбоя.'),
              subtitle: Text('После остановки выполните LOCK, затем UNLOCK.'),
            ),
          if (message != null) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(message),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: canLock ? () => perform(ble.lockScooter) : null,
                icon: const Icon(Icons.lock),
                label: const Text('LOCK'),
              ),
              FilledButton.icon(
                onPressed: canUnlock ? () => perform(ble.unlockScooter) : null,
                icon: const Icon(Icons.lock_open),
                label: const Text('UNLOCK'),
              ),
              OutlinedButton.icon(
                onPressed: canUseLight ? () => perform(ble.toggleScooterLight) : null,
                icon: const Icon(Icons.lightbulb_outline),
                label: Text(ble.lightOn == true ? 'LIGHT OFF' : 'LIGHT ON'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
