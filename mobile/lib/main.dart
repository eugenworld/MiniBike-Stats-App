import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:minibike_stats/services/minibike_ble.dart';
import 'tests.dart';

void main() => runApp(ChangeNotifierProvider(create: (_) => MiniBikeBle(), child: const MiniBikeStatsApp()));
class MiniBikeStatsApp extends StatelessWidget {
  const MiniBikeStatsApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title: 'MiniBike Stats',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark), useMaterial3: true),
    home: const DashboardScreen(), debugShowCheckedModeBanner: false);
}
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override Widget build(BuildContext context) {
    final ble=context.watch<MiniBikeBle>();
    Future<void> action(Future<void> Function() fn) async {
      try { await fn(); } catch(e) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    }
    Widget stat(String label) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children:[Text(label), const Text('—',style:TextStyle(fontSize:25)),const Text('Not decoded',style:TextStyle(fontSize:11))])));
    return Scaffold(appBar: AppBar(title:const Text('ES200 • MiniBike Stats')),
      body: ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:ListTile(title:Text(ble.statusMessage),subtitle:const Text('ESP32 BLE connection'),trailing:FilledButton(
          onPressed:ble.isScanning?null:()=>action(ble.isConnected?ble.disconnect:ble.connect),
          child:Text(ble.isConnected?'Disconnect':'Connect')))),
        const SizedBox(height:10),
        Wrap(spacing:8,runSpacing:8,children:[stat('Battery'),stat('Speed'),stat('Motor current'),stat('Voltage')]),
        const SizedBox(height:12),
        Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('ES200G controls'),const SizedBox(height:8),
          Wrap(spacing:8,children:[
            OutlinedButton.icon(onPressed:!ble.isConnected?null:()=>action(ble.unlocked==true?ble.lockScooter:ble.unlockScooter),
              icon:Icon(ble.unlocked==true?Icons.lock:Icons.lock_open),label:Text(ble.unlocked==true?'LOCK':'UNLOCK')),
            OutlinedButton.icon(onPressed:!ble.isConnected?null:()=>action(ble.toggleScooterLight),
              icon:Icon(ble.lightOn==true?Icons.lightbulb:Icons.lightbulb_outline),
              label:Text(ble.lightOn==null?'LIGHT ?':ble.lightOn!?'LIGHT ON':'LIGHT OFF')),
          ]),const SizedBox(height:8),const Text('Light/lock: ESP32 commanded state, not confirmed by YL ECU.',style:TextStyle(fontSize:11))
        ]))),
        const SizedBox(height:12),FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const TestsScreen())),icon:const Icon(Icons.science),label:const Text('Tests & recordings')),
        const SizedBox(height:12),const Text('Unknown telemetry is shown as —, not zero. Do not use this prototype for road riding.',style:TextStyle(fontSize:12))
      ]));
  }
}
