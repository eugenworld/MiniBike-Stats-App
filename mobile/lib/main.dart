import 'package:flutter/material.dart';
import 'package:minibike_stats/services/minibike_ble.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(ChangeNotifierProvider(
      create: (_) => MiniBikeBle(),
      child: const MiniBikeStatsApp(),
    ));

class MiniBikeStatsApp extends StatefulWidget {
  const MiniBikeStatsApp({super.key});

  @override
  State<MiniBikeStatsApp> createState() => _MiniBikeStatsAppState();
}

class _MiniBikeStatsAppState extends State<MiniBikeStatsApp> {
  ThemeMode _theme = ThemeMode.system;
  bool _miles = false;
  bool _showMetrics = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _theme = ThemeMode.values.asNameMap()[preferences.getString('theme')] ??
          ThemeMode.system;
      _miles = preferences.getBool('miles') ?? false;
      _showMetrics = preferences.getBool('showMetrics') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('theme', _theme.name);
    await preferences.setBool('miles', _miles);
    await preferences.setBool('showMetrics', _showMetrics);
  }

  ThemeData _makeTheme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff16675a),
      brightness: brightness,
    );
    return ThemeData(colorScheme: colors, useMaterial3: true);
  }

  String _distance(double? kilometers) {
    if (kilometers == null || !kilometers.isFinite) return '—';
    final value = _miles ? kilometers / 1.609344 : kilometers;
    return '${value.toStringAsFixed(1)} ${_miles ? 'ми' : 'км'}';
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MiniBike Stats',
        theme: _makeTheme(Brightness.light),
        darkTheme: _makeTheme(Brightness.dark),
        themeMode: _theme,
        debugShowCheckedModeBanner: false,
        home: Builder(builder: (context) {
          final ble = context.watch<MiniBikeBle>();
          const titles = ['Мой самокат', 'Поездки', 'Настройки', 'Администратор'];
          return Scaffold(
            appBar: AppBar(title: Text(titles[_page])),
            body: SafeArea(
              child: switch (_page) {
                0 => DashboardScreen(
                    distance: _distance,
                    showMetrics: _showMetrics,
                  ),
                1 => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.route_outlined, size: 40),
                          SizedBox(height: 12),
                          Text('История поездок недоступна в этой сборке.'),
                        ],
                      ),
                    ),
                  ),
                2 => _settings(),
                _ => _administrator(ble),
              },
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (index) => setState(() => _page = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.electric_scooter), label: 'Самокат',
                ),
                NavigationDestination(
                  icon: Icon(Icons.route_outlined), label: 'Поездки',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined), label: 'Настройки',
                ),
                NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings_outlined), label: 'Админ',
                ),
              ],
            ),
          );
        }),
      );

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(title: Text('Язык'), subtitle: Text('Русский')),
          ListTile(
            title: const Text('Тема'),
            trailing: DropdownButton<ThemeMode>(
              value: _theme,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('Системная')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Светлая')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Тёмная')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _theme = value);
                _saveSettings();
              },
            ),
          ),
          ListTile(
            title: const Text('Единицы измерения'),
            trailing: DropdownButton<bool>(
              value: _miles,
              items: const [
                DropdownMenuItem(value: false, child: Text('Километры')),
                DropdownMenuItem(value: true, child: Text('Мили')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _miles = value);
                _saveSettings();
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Показывать пробег'),
            value: _showMetrics,
            onChanged: (value) {
              setState(() => _showMetrics = value);
              _saveSettings();
            },
          ),
          const ListTile(
            title: Text('Громкость динамика'),
            subtitle: Slider(value: 0, onChanged: null),
          ),
          const ListTile(
            title: Text('Очистить историю поездок'),
            trailing: Icon(Icons.delete_outline),
            enabled: false,
          ),
          const ListTile(
            title: Text('Версия'),
            subtitle: Text('ES200 · сборка для проверки интерфейса'),
          ),
        ],
      );

  Widget _administrator(MiniBikeBle ble) {
    final limit = ble.speedLimit;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Вход администратора'),
        const SizedBox(height: 12),
        const TextField(
          enabled: false,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Пароль',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const FilledButton(onPressed: null, child: Text('Войти')),
        const SizedBox(height: 12),
        const Text('Вход и изменение параметров ESP32 пока недоступны.'),
        const Divider(height: 32),
        ListTile(
          title: const Text('Ограничение скорости'),
          subtitle: Text(limit == null
              ? '—'
              : limit == 255 ? 'Без ограничения' : '$limit км/ч'),
          leading: const Icon(Icons.speed),
        ),
        const ListTile(title: Text('Сменить пароль'), enabled: false),
        const ListTile(title: Text('Google Drive'), enabled: false),
      ],
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.distance,
    required this.showMetrics,
  });

  final String Function(double?) distance;
  final bool showMetrics;

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<MiniBikeBle>();
    final phase = ble.phase;
    final speed = ble.latestTelemetry?.speedKmh;
    final soc = ble.latestTelemetry?.soc;
    final fresh = speed != null && speed.isFinite;
    final ready = ble.isConnected && !ble.isScanning && phase != null && fresh;
    final canWake = ble.isConnected && !fresh && ble.canWakeController;
    final canLock = canWake || ble.isConnected && !ble.isScanning &&
        speed != null && speed.isFinite &&
        (phase == 0 && speed == 0 || phase == 4 && speed <= 2);
    final canUnlock = ready && phase == 2 && ble.actualUnlocked == false &&
        !ble.charging && speed == 0;
    final canUseLight = ready && phase == 4 && ble.actualUnlocked == true &&
        ble.lightOn != null;

    final status = switch (phase) {
      0 when fresh && speed == 0 => 'Нажмите LOCK для подтверждения блокировки.',
      0 => 'Дождитесь остановки самоката.',
      1 || 5 => 'Блокировка…',
      2 when ble.actualUnlocked == false => 'Самокат заблокирован',
      3 => 'Разблокировка…',
      4 when ble.actualUnlocked == true => 'Самокат разблокирован',
      _ => null,
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

    final theme = Theme.of(context);
    final battery = soc != null && soc.isFinite
        ? '${soc.toStringAsFixed(0)} %'
        : '—';
    final minutes = ble.chargingMinutes;
    final chargingTime = minutes == null
        ? 'Расчёт времени…'
        : minutes == 0
            ? 'Заряд достиг 100 %'
            : 'До полного заряда ≈ ${minutes ~/ 60} ч ${minutes % 60} мин';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(ble.isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
            title: Text(ble.isConnected
                ? 'ESP32 подключена'
                : ble.isScanning ? 'Подключение…' : 'Отключено'),
            subtitle: ble.isConnected
                ? Text(fresh ? 'Контроллер на связи' : 'Нет телеметрии контроллера')
                : null,
            trailing: TextButton(
              onPressed: ble.isScanning
                  ? null
                  : () => perform(ble.isConnected ? ble.disconnect : ble.connect),
              child: Text(ble.isConnected ? 'Отключить' : 'Подключить'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  ble.charging ? Icons.battery_charging_full : Icons.electric_scooter,
                  size: 50,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ble.charging ? 'Идёт зарядка' : 'Батарея'),
                      Text(battery, style: theme.textTheme.displaySmall),
                      if (ble.charging) Text(chargingTime),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showMetrics) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _metric('Пробег, всего', distance(ble.odometerKm),
                    note: ble.odometerKm == null ? null : 'Предварительная оценка'),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _metric('Текущая / последняя поездка', distance(ble.latestTelemetry?.tripKm)),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _metric('Пробег с заряда', '—'),
              ],
            ),
          ),
        ],
        if (!ble.charging) ...[
          const SizedBox(height: 20),
          Text('Управление', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (ble.isConnected && !fresh)
            Text(canWake
                ? 'Включите контроллер, чтобы получить телеметрию.'
                : 'Ожидание телеметрии самоката.')
          else if (status != null)
            Text(status),
          if (phase == 0 && const [4, 5, 6, 7].contains(ble.resetReason))
            const Text('ESP32 перезапустилась. После остановки выполните LOCK, затем UNLOCK.'),
          if (message != null) Text(message),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: canLock ? () => perform(ble.lockScooter) : null,
                icon: const Icon(Icons.lock_outline),
                label: Text(canWake ? 'Включить контроллер' : 'LOCK'),
              ),
              FilledButton.icon(
                onPressed: canUnlock ? () => perform(ble.unlockScooter) : null,
                icon: const Icon(Icons.lock_open),
                label: const Text('UNLOCK'),
              ),
              OutlinedButton.icon(
                onPressed: canUseLight ? () => perform(ble.toggleScooterLight) : null,
                icon: Icon(ble.lightOn == true ? Icons.lightbulb : Icons.lightbulb_outline),
                label: Text(ble.lightOn == true ? 'Выключить свет' : 'Включить свет'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _metric(String label, String value, {String? note}) => ListTile(
        title: Text(label),
        subtitle: note == null ? null : Text(note),
        trailing: Text(value),
      );
}
