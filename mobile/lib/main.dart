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
          const titles = ['Мой самокат', 'Настройки', 'Администратор'];
          return Scaffold(
            appBar: AppBar(title: Text(titles[_page])),
            body: SafeArea(
              child: switch (_page) {
                0 => DashboardScreen(
                    distance: _distance,
                    showMetrics: _showMetrics,
                  ),
                1 => _settings(),
                _ => _Administrator(ble: ble),
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
            title: Text('Версия'),
            subtitle: Text('ES200 · 1.0'),
          ),
        ],
      );

}
  
class _Administrator extends StatefulWidget {
  const _Administrator({required this.ble});
  final MiniBikeBle ble;

  @override
  State<_Administrator> createState() => _AdministratorState();
}

class _AdministratorState extends State<_Administrator> {
  final _pin = TextEditingController();
  final _newPin = TextEditingController();
  final _limit = TextEditingController();
  bool _busy = false;
  bool _unlimited = false;
  String? _authorizedPin;
  String? _message;

  bool _validPin(String pin) => RegExp(r'^[0-9]{6}$').hasMatch(pin);

  @override
  void didUpdateWidget(covariant _Administrator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.ble.isConnected) {
      _authorizedPin = null;
      _pin.clear();
      _newPin.clear();
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _newPin.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _send(int operation) async {
    final pin = operation == 0x40 ? _pin.text : _authorizedPin;
    if (pin == null || !_validPin(pin)) {
      setState(() => _message = 'Введите пароль из шести цифр.');
      return;
    }
    final next = _newPin.text;
    final limit = _unlimited ? 255 : int.tryParse(_limit.text);
    final argument = <int>[];
    if (operation == 0x41) {
      if (limit == null || (!_unlimited && (limit < 1 || limit > 40))) {
        setState(() => _message = 'Введите целое число от 1 до 40 км/ч.');
        return;
      }
      argument.add(limit);
    }
    if (operation == 0x42) {
      if (!_validPin(next)) {
        setState(() => _message = 'Новый пароль должен состоять из шести цифр.');
        return;
      }
      argument.addAll(next.codeUnits);
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final reply = await widget.ble.adminCommand(operation, pin, argument);
      if (!mounted) return;
      if (reply == 0 && operation == 0x40 && widget.ble.isConnected) {
        _authorizedPin = pin;
        _pin.clear();
        final applied = widget.ble.speedLimit;
        _unlimited = applied == 255;
        _limit.text = applied == null || applied == 255 ? '' : '$applied';
      }
      if (reply == 0 && operation == 0x42 && widget.ble.isConnected) {
        _authorizedPin = next;
        _newPin.clear();
      }
      if (reply == 1 || reply == 2 || reply == 7) _authorizedPin = null;
      _message = switch (reply) {
        0 when operation == 0x41 => 'Лимит сохранён в ESP32.',
        0 when operation == 0x42 => 'Пароль изменён.',
        0 => null,
        1 => 'Неверный пароль.',
        2 => 'Слишком много попыток. Подождите 30 секунд.',
        3 => 'Остановите и заблокируйте самокат.',
        4 => 'Ошибка памяти ESP32.',
        5 => 'ESP32 отклонила значение.',
        _ => 'Связь с ESP32 прервана.',
      };
    } catch (_) {
      if (mounted) _message = 'Нет ответа. Проверьте подключение и сопряжение Bluetooth.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = widget.ble;
    if (!ble.isConnected || !ble.supportsAdmin) {
      return Center(child: Text(ble.isConnected
          ? 'Обновите прошивку ESP32 до версии 1.0.'
          : 'Подключитесь к самокату.'));
    }
    final limit = ble.speedLimit;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_authorizedPin == null) ...[
          TextField(
            controller: _pin,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Пароль администратора'),
          ),
          FilledButton(onPressed: _busy ? null : () => _send(0x40), child: const Text('Войти')),
        ] else ...[
          ListTile(
            title: const Text('Текущий лимит'),
            subtitle: Text(limit == 255 ? 'Без ограничения' : limit == null ? '—' : '$limit км/ч'),
          ),
          SwitchListTile(
            title: const Text('Без ограничения'),
            value: _unlimited,
            onChanged: _busy ? null : (value) => setState(() => _unlimited = value),
          ),
          if (!_unlimited)
            TextField(
              controller: _limit,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Лимит, км/ч (1–40)'),
            ),
          if (!ble.canSetSpeedLimit)
            const Text('Для изменения лимита остановите и заблокируйте самокат.'),
          FilledButton(
            onPressed: _busy || !ble.canSetSpeedLimit ? null : () => _send(0x41),
            child: const Text('Сохранить лимит'),
          ),
          const Divider(),
          TextField(
            controller: _newPin,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Новый пароль'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _send(0x42),
            child: const Text('Сменить пароль'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() {
              _authorizedPin = null;
              _newPin.clear();
              _message = null;
            }),
            child: const Text('Выйти'),
          ),
        ],
        if (_message != null) Text(_message!),
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
    final showLock = phase == 4 && ble.actualUnlocked == true;
    final canLock = ready && phase == 4 && showLock && speed <= 2;
    final canUnlock = ble.isConnected && !ble.isScanning &&
        ble.unlockPermission == 0 && !showLock;
    final canUseLight = ready && phase == 4 && ble.actualUnlocked == true &&
        ble.lightOn != null;

    final unlockBlock = !ble.isConnected || canUnlock || showLock ||
            (phase != 0 && phase != 2)
        ? null
        : switch (ble.unlockPermission) {
            1 => 'Нет свежей телеметрии контроллера.',
            2 => 'Контроллер сообщает ненулевую скорость.',
            4 => 'Разблокировка недоступна в текущем режиме.',
            5 => 'Синхронизация с телефоном…',
            7 => 'Ожидание второго кадра с нулевой скоростью.',
            _ => null,
          };
    final status = unlockBlock ?? switch (phase) {
      0 when ble.actualUnlocked == false => 'Самокат заблокирован',
      0 when canUnlock => 'Можно разблокировать',
      0 when fresh => 'Ожидание готовности контроллера.',
      1 => 'Блокировка…',
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
      6 => 'Контроллер не подтвердил разблокировку за 4 секунды.',
      7 => 'Ожидание второго кадра с нулевой скоростью.',
      8 => 'Самокат уже разблокирован.',
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
              ],
            ),
          ),
        ],
        ...[
          const SizedBox(height: 20),
          Text('Управление', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (unlockBlock == null && ble.isConnected && !fresh && !canUnlock)
            const Text('Ожидание телеметрии самоката.')
          else if (status != null)
            Text(status),
          if (ble.isConnected && phase != null && ble.unlockPermission == null)
            const Text('Для управления обновите прошивку ESP32.'),
          if (message != null) Text(message),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: canLock
                    ? () => perform(ble.lockScooter)
                    : canUnlock
                        ? () => perform(ble.unlockScooter)
                        : null,
                icon: Icon(showLock ? Icons.lock_outline : Icons.lock_open),
                label: Text(showLock ? 'LOCK' : 'UNLOCK'),
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
