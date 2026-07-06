import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:brilliant_msg/tx/code.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

// Frame to Phone flags
const notifMsg = 0x0B;

// Phone to Frame flags
const startAncsMsg = 0x40;
const stopAncsMsg = 0x41;

/// Fields in a notification message are joined with the ASCII unit
/// separator, which cannot occur inside UTF-8 text
const fieldSep = 0x1F;

/// One iOS notification as reported by the Halo (via the ANCS client
/// running in the frame.ancs Lua API)
class AncsNotification {
  final int uid;
  String category;
  String title = '';
  String message = '';
  String app = '';
  String lastEvent;

  AncsNotification(this.uid, this.category, this.lastEvent);

  IconData get icon => switch (category) {
        'incoming_call' => Icons.call,
        'missed_call' => Icons.phone_missed,
        'voicemail' => Icons.voicemail,
        'social' => Icons.chat,
        'schedule' => Icons.event,
        'email' => Icons.email,
        'news' => Icons.newspaper,
        'health_and_fitness' => Icons.fitness_center,
        'business_and_finance' => Icons.business,
        'location' => Icons.location_on,
        'entertainment' => Icons.movie,
        _ => Icons.notifications,
      };
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  StreamSubscription<List<int>>? _notifStreamSubs;

  /// newest first
  final List<AncsNotification> _notifications = [];
  bool _ancsAvailable = false;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  void _handleNotifMessage(List<int> data) {
    // strip the flag byte, split on the unit separator
    final fields = utf8
        .decode(data.sublist(1), allowMalformed: true)
        .split(String.fromCharCode(fieldSep));
    if (fields.isEmpty) return;

    final kind = fields[0];
    final uid = fields.length > 1 ? int.tryParse(fields[1]) ?? 0 : 0;
    final category = fields.length > 2 ? fields[2] : '';
    final title = fields.length > 3 ? fields[3] : '';
    final message = fields.length > 4 ? fields[4] : '';
    final app = fields.length > 5 ? fields[5] : '';

    _log.fine(() => 'ANCS event: $kind uid=$uid $category $title');

    setState(() {
      switch (kind) {
        case 'available':
          _ancsAvailable = true;
        case 'unavailable':
          _ancsAvailable = false;
          _notifications.clear();
        case 'removed':
          _notifications.removeWhere((n) => n.uid == uid);
        case 'added' || 'modified':
          _ancsAvailable = true; // notification traffic implies availability
          var n = _notifications.where((n) => n.uid == uid).firstOrNull;
          if (n == null) {
            n = AncsNotification(uid, category, kind);
            _notifications.insert(0, n);
            if (_notifications.length > 50) {
              _notifications.removeLast();
            }
          } else {
            n.category = category;
            n.lastEvent = kind;
          }
        case 'attrs':
          final n = _notifications.where((n) => n.uid == uid).firstOrNull;
          if (n != null) {
            n.title = title;
            n.message = message;
            n.app = app;
          }
      }
    });
  }

  @override
  Future<void> run() async {
    setState(() {
      currentState = ApplicationState.running;
      _notifications.clear();
    });

    try {
      // listen for notification events forwarded by the frameside app
      await _notifStreamSubs?.cancel();
      _notifStreamSubs = frame!.dataResponse
          .where((data) => data.isNotEmpty && data[0] == notifMsg)
          .listen(_handleNotifMessage);

      // ask the frameside app to subscribe to ANCS; iOS then replays all
      // current notifications followed by live events
      await frame!.sendMessage(startAncsMsg, TxCode(value: 1).pack());
    } catch (e) {
      _log.severe(() => 'Error executing application logic: $e');
      setState(() {
        currentState = ApplicationState.ready;
      });
    }
  }

  @override
  Future<void> cancel() async {
    // unsubscribe from ANCS on the frameside
    await frame!.sendMessage(stopAncsMsg, TxCode().pack());
    await _notifStreamSubs?.cancel();

    setState(() {
      currentState = ApplicationState.ready;
      _ancsAvailable = false;
    });
  }

  @override
  void dispose() async {
    await _notifStreamSubs?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Halo ANCS Demo',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
            title: const Text('Halo ANCS Demo'), actions: [getBatteryWidget()]),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (currentState == ApplicationState.running)
                Card(
                  child: ListTile(
                    leading: Icon(
                        _ancsAvailable
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        color: _ancsAvailable ? Colors.green : Colors.orange),
                    title: Text(_ancsAvailable
                        ? 'ANCS active - this phone\'s notifications show on the Halo'
                        : 'ANCS not available'),
                    subtitle: _ancsAvailable
                        ? Text('${_notifications.length} notifications')
                        : const Text(
                            'ANCS is served by iOS only, and requires the Halo '
                            'to be bonded to this phone (encrypted link)'),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: _notifications.isEmpty
                    ? const Center(
                        child: Text(
                            'Connect and Start, then notifications from this '
                            'iPhone appear here and on the Halo display.',
                            textAlign: TextAlign.center))
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          return Card(
                            child: ListTile(
                              leading: Icon(n.icon),
                              title: Text(
                                  n.title.isNotEmpty ? n.title : n.category),
                              subtitle: Text([
                                if (n.message.isNotEmpty) n.message,
                                if (n.app.isNotEmpty) n.app,
                              ].join('\n')),
                              trailing: Text('#${n.uid}\n${n.lastEvent}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          );
                        }),
              ),
            ],
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(
            const Icon(Icons.notifications_active), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
