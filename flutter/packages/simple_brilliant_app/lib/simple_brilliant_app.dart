import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:brilliant_ble/brilliant_bluetooth.dart';
import 'package:brilliant_ble/brilliant_connection_state.dart';
import 'package:brilliant_ble/brilliant_device.dart';
import 'package:brilliant_ble/brilliant_scanned_device.dart';
import 'package:brilliant_msg/tx/sprite.dart';

/// basic State Machine for the app; mostly for bluetooth lifecycle,
/// all app activity expected to take place during "running" state
enum ApplicationState {
  initializing,
  disconnected,
  scanning,
  connecting,
  connected,
  starting,
  ready,
  running,
  canceling,
  stopping,
  disconnecting,
}

final _log = Logger("SFA");

mixin SimpleFrameAppState<T extends StatefulWidget> on State<T> {

  ApplicationState currentState = ApplicationState.disconnected;

  // Frame to Phone flags
  static const batteryStatusFlag = 0x0c;

  int? _batt;
  // make battery level available to implementing apps
  int get batteryLevel => _batt ?? 0;

  // Use BrilliantBluetooth for communications with Frame
  BrilliantDevice? frame;
  StreamSubscription<BrilliantScannedDevice>? _scanStream;
  StreamSubscription<BrilliantDevice>? _deviceStateSubs;
  StreamSubscription<List<int>>? _rxAppData;
  StreamSubscription<String>? _rxStdOut;

  Future<void> scanForFrame() async {
    currentState = ApplicationState.scanning;
    if (mounted) setState(() {});

    // create a Future we can manually complete when Frame is found
    // or timeout occurred, but either way we can await scanForFrame synchronously
    final completer = Completer<void>();

    await BrilliantBluetooth.requestPermission();

    await _scanStream?.cancel();
    _scanStream = BrilliantBluetooth.scan().timeout(const Duration(seconds: 5),
        onTimeout: (sink) {
      // Scan timeouts can occur without having found a Frame, but also
      // after the Frame is found and being connected to, even though
      // the first step after finding the Frame is to stop the scan.
      // In those cases we don't want to change the application state back
      // to disconnected
      switch (currentState) {
        case ApplicationState.scanning:
          _log.fine('Scan timed out after 5 seconds');
          currentState = ApplicationState.disconnected;
          if (mounted) setState(() {});
          break;
        case ApplicationState.connecting:
          // found a device and started connecting, just let it play out
          break;
        case ApplicationState.connected:
        case ApplicationState.ready:
        case ApplicationState.running:
        case ApplicationState.starting:
        case ApplicationState.canceling:
          // already connected, nothing to do
          break;
        default:
          _log.fine('Unexpected state on scan timeout: $currentState');
          if (mounted) setState(() {});

        // signal that scanForFrame can now finish
        // if it hasn't already completed via the listen() path below
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }).listen((device) async {
      _log.fine('Frame found, connecting');
      currentState = ApplicationState.connecting;
      if (mounted) setState(() {});

      await connectToScannedFrame(device);

      // signal that scanForFrame can now finish
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // wait until the listen(onData) or the onTimeout is completed
    // so we can return synchronously
    await completer.future;
  }

  Future<void> connectToScannedFrame(BrilliantScannedDevice device) async {
    try {
      _log.fine('connecting to scanned device: $device');
      frame = await BrilliantBluetooth.connect(device);
      _log.fine('device connected: ${frame!.device.remoteId}');

      // subscribe to connection state for the device to detect disconnections
      // so we can transition the app to a disconnected state
      await _refreshDeviceStateSubs();

      // refresh subscriptions to String rx and Data rx
      await _refreshRxSubs();

      try {
        // terminate the main.lua (if currently running) so we can run our lua code
        // TODO looks like if the signal comes too early after connection, it isn't registered
        await Future.delayed(const Duration(milliseconds: 500));
        await frame!.sendBreakSignal();
        await Future.delayed(const Duration(milliseconds: 500));

        await frame!.sendString(
            'print("Connected to " .. frame.HARDWARE_VERSION .. " " .. frame.FIRMWARE_VERSION .. ", Mem: " .. tostring(collectgarbage("count")))',
            awaitResponse: true);

        // Frame is ready to go!
        currentState = ApplicationState.connected;
        if (mounted) setState(() {});
      } catch (e) {
        currentState = ApplicationState.disconnected;
        _log.fine('Error while sending break signal: $e');
        if (mounted) setState(() {});

        await disconnectFrame();
      }
    } catch (e) {
      currentState = ApplicationState.disconnected;
      _log.fine('Error while connecting and/or discovering services: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> reconnectFrame() async {
    if (frame != null) {
      try {
        _log.fine('reconnecting to existing device: $frame');
        // TODO get the BrilliantDevice return value from the reconnect call?
        // TODO am I getting duplicate devices/subscriptions?
        // Rather than fromUuid(), can I just call connectedDevice.device.connect() myself?
        await BrilliantBluetooth.reconnect(frame!.uuid);
        _log.fine('device connected: $frame');

        // subscribe to connection state for the device to detect disconnections
        // and transition the app to a disconnected state
        await _refreshDeviceStateSubs();

        // refresh subscriptions to String rx and Data rx
        await _refreshRxSubs();

        try {
          // terminate the main.lua (if currently running) so we can run our lua code
          // TODO looks like if the signal comes too early after connection, it isn't registered
          await Future.delayed(const Duration(milliseconds: 500));
          await frame!.sendBreakSignal();
          await Future.delayed(const Duration(milliseconds: 500));

          await frame!.sendString(
              'print("Connected to Frame " .. frame.FIRMWARE_VERSION .. ", Mem: " .. tostring(collectgarbage("count")))',
              awaitResponse: true);

          // Frame is ready to go!
          currentState = ApplicationState.connected;
          if (mounted) setState(() {});
        } catch (e) {
          currentState = ApplicationState.disconnected;
          _log.fine('Error while sending break signal: $e');
          if (mounted) setState(() {});

          await disconnectFrame();
        }
      } catch (e) {
        currentState = ApplicationState.disconnected;
        _log.fine('Error while connecting and/or discovering services: $e');
        if (mounted) setState(() {});
      }
    } else {
      currentState = ApplicationState.disconnected;
      _log.fine('Current device is null, reconnection not possible');
      if (mounted) setState(() {});
    }
  }

  Future<void> scanOrReconnectFrame() async {
    if (frame != null) {
      await reconnectFrame();
    } else {
      await scanForFrame();
    }
  }

  Future<void> disconnectFrame() async {
    if (frame != null) {
      try {
        _log.fine('Disconnecting from Frame');
        // break first in case it's sleeping - otherwise the reset won't work
        await frame!.sendBreakSignal();
        _log.fine('Break signal sent');
        // TODO the break signal needs some more time to be processed before we can reliably send the reset signal, by the looks of it
        await Future.delayed(const Duration(milliseconds: 500));

        // cancel the stdout and data subscriptions
        _rxStdOut?.cancel();
        _log.fine('StdOut subscription canceled');
        _rxAppData?.cancel();
        _log.fine('AppData subscription canceled');

        // try to reset device back to running main.lua
        await frame!.sendResetSignal();
        _log.fine('Reset signal sent');
        // TODO the reset signal doesn't seem to be processed in time if we disconnect immediately, so we introduce a delay here to give it more time
        // The sdk's sendResetSignal actually already adds 100ms delay
        // perhaps it's not quite enough.
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        _log.fine('Error while sending reset signal: $e');
      }

      try {
        // try to disconnect cleanly if the device allows
        await frame!.disconnect();
      } catch (e) {
        _log.fine('Error while calling disconnect(): $e');
      }
    } else {
      _log.fine('Current device is null, disconnection not possible');
    }

    _batt = null;
    currentState = ApplicationState.disconnected;
    if (mounted) setState(() {});
  }

  Future<void> _refreshDeviceStateSubs() async {
    await _deviceStateSubs?.cancel();
    _deviceStateSubs = frame!.connectionState.listen((bcs) {
      _log.fine(() => 'Frame connection state change: $bcs');

      // notice disconnections and set ApplicationState to reflect that
      if (bcs.state == BrilliantConnectionState.disconnected) {
        currentState = ApplicationState.disconnected;
        _log.fine('Frame disconnected');
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _refreshRxSubs() async {
    await _rxAppData?.cancel();
    _rxAppData = frame!.dataResponse.listen((data) {
      if (data.length > 1) {
        // at this stage simple frame app only handles battery level message 0x0c
        // let any other application-specific message be handled by the app when
        // they listen on dataResponse
        if (data[0] == batteryStatusFlag) {
          _batt = data[1];
          if (mounted) setState(() {});
        }
      }
    });

    // subscribe one listener to the stdout stream
    await _rxStdOut?.cancel();
    _rxStdOut = frame!.stringResponse.listen((data) {});
  }

  Widget getBatteryWidget() {
    if (_batt == null) return Container();

    IconData i;
    if (_batt! > 87.5) {
      i = Icons.battery_full;
    } else if (_batt! > 75) {
      i = Icons.battery_6_bar;
    } else if (_batt! > 62.5) {
      i = Icons.battery_5_bar;
    } else if (_batt! > 50) {
      i = Icons.battery_4_bar;
    } else if (_batt! > 45) {
      i = Icons.battery_3_bar;
    } else if (_batt! > 25) {
      i = Icons.battery_2_bar;
    } else if (_batt! > 12.5) {
      i = Icons.battery_1_bar;
    } else {
      i = Icons.battery_0_bar;
    }

    return Row(children: [
      Text('$_batt%'),
      Icon(
        i,
        size: 16,
      )
    ]);
  }

  List<Widget> getFooterButtonsWidget() {
    // work out the states of the footer buttons based on the app state
    List<Widget> pfb = [];

    switch (currentState) {
      case ApplicationState.disconnected:
        pfb.add(TextButton(
            onPressed: scanOrReconnectFrame, child: const Text('Connect')));
        pfb.add(const TextButton(onPressed: null, child: Text('Start')));
        pfb.add(const TextButton(onPressed: null, child: Text('Stop')));
        pfb.add(const TextButton(onPressed: null, child: Text('Disconnect')));
        break;

      case ApplicationState.initializing:
      case ApplicationState.scanning:
      case ApplicationState.connecting:
      case ApplicationState.starting:
      case ApplicationState.running:
      case ApplicationState.canceling:
      case ApplicationState.stopping:
      case ApplicationState.disconnecting:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect')));
        pfb.add(const TextButton(onPressed: null, child: Text('Start')));
        pfb.add(const TextButton(onPressed: null, child: Text('Stop')));
        pfb.add(const TextButton(onPressed: null, child: Text('Disconnect')));
        break;

      case ApplicationState.connected:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect')));
        pfb.add(TextButton(
            onPressed: startApplication, child: const Text('Start')));
        pfb.add(const TextButton(onPressed: null, child: Text('Stop')));
        pfb.add(TextButton(
            onPressed: disconnectFrame, child: const Text('Disconnect')));
        break;

      case ApplicationState.ready:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect')));
        pfb.add(const TextButton(onPressed: null, child: Text('Start')));
        pfb.add(
            TextButton(onPressed: stopApplication, child: const Text('Stop')));
        pfb.add(const TextButton(onPressed: null, child: Text('Disconnect')));
        break;
    }
    return pfb;
  }

  FloatingActionButton? getFloatingActionButtonWidget(
      Icon ready, Icon running) {
    return currentState == ApplicationState.ready
        ? FloatingActionButton(onPressed: run, child: ready)
        : currentState == ApplicationState.running
            ? FloatingActionButton(onPressed: cancel, child: running)
            : null;
  }

  /// the SimpleFrameApp subclass can override with application-specific code if necessary
  Future<void> startApplication() async {
    currentState = ApplicationState.starting;
    if (mounted) setState(() {});

    // try to get the Frame into a known state by making sure there's no main loop running
    frame!.sendBreakSignal();
    await Future.delayed(const Duration(milliseconds: 500));

    // clear the previous content from the display and show a temporary loading screen while
    // we send over our scripts and resources
    await showLoadingScreen();
    await Future.delayed(const Duration(milliseconds: 100));

    // only if there are lua files to send to Frame (e.g. frame_app.lua companion app, other helper functions, minified versions)
    List<String> luaFiles = _filterLuaFiles(
        (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets());

    _log.info("Lua asset files: $luaFiles");

    if (luaFiles.isNotEmpty) {
      for (var pathFile in luaFiles) {
        String fileName = pathFile.split('/').last;
        // send the lua script to the Frame
        await frame!.uploadScript(fileName, await rootBundle.loadString(pathFile));
      }

      await frame!.sendString(
          'print("Memory use after uploading scripts: " .. tostring(collectgarbage("count")))',
          awaitResponse: true);

      // kick off the main application loop: if there is only one lua file, use it;
      // otherwise require a file called "assets/frame_app.min.lua", or "assets/frame_app.lua".
      // In that case, the main app file should add require() statements for any dependent modules
      if (luaFiles.length != 1 &&
          !luaFiles.contains('assets/frame_app.min.lua') &&
          !luaFiles.contains('assets/frame_app.lua')) {
        _log.fine('Multiple Lua files uploaded, but no main file to require()');
      } else {
        if (luaFiles.length == 1) {
          String fileName = luaFiles[0]
              .split('/')
              .last; // e.g. "assets/my_file.min.lua" -> "my_file.min.lua"
          int lastDotIndex = fileName.lastIndexOf(".lua");
          String bareFileName = fileName.substring(
              0, lastDotIndex); // e.g. "my_file.min.lua" -> "my_file.min"

          await frame!
              .sendString('require("$bareFileName")', awaitResponse: true);
        } else if (luaFiles.contains('assets/frame_app.min.lua')) {
          await frame!
              .sendString('require("frame_app.min")', awaitResponse: true);
        } else if (luaFiles.contains('assets/frame_app.lua')) {
          await frame!.sendString('require("frame_app")', awaitResponse: true);
        }

        // load all the Sprites from assets/sprites
        await _uploadSprites(_filterSpriteAssets(
            (await AssetManifest.loadFromAssetBundle(rootBundle))
                .listAssets()));
      }
    } else {
      await frame!.clearDisplay();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  /// the SimpleFrameApp subclass can override with application-specific code if necessary
  Future<void> stopApplication() async {
    currentState = ApplicationState.stopping;
    if (mounted) setState(() {});

    // send a break to stop the Lua app loop on Frame
    await frame!.sendBreakSignal();
    await Future.delayed(const Duration(milliseconds: 500));

    // only if there are lua files uploaded to Frame (e.g. frame_app.lua companion app, other helper functions, minified versions)
    List<String> luaFiles = _filterLuaFiles(
        (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets());

    if (luaFiles.isNotEmpty) {
      // clean up by deregistering any handler
      await frame!.sendString('frame.bluetooth.receive_callback(nil);print(0)',
          awaitResponse: true);

      for (var file in luaFiles) {
        // delete any prior scripts
        await frame!.sendString(
            'frame.file.remove("${file.split('/').last}");print(0)',
            awaitResponse: true);
      }
    }

    currentState = ApplicationState.connected;
    if (mounted) setState(() {});
  }

  /// When given the full list of Assets, return only the Lua files
  /// Note that returned file strings will be 'assets/my_file.lua' or 'assets/my_other_file.min.lua' which we need to use to find the asset in Flutter,
  /// but we need to file.split('/').last if we only want the file name when writing/deleting the file on Frame in the root of its filesystem
  List<String> _filterLuaFiles(List<String> files) {
    return files.where((name)=>name.endsWith('.lua')).toList();
  }

  /// Loops over each of the sprites in the assets/sprites directory (and declared in pubspec.yaml) and returns an entry with
  /// each sprite associated with a message_type key: the two hex digits in its filename,
  /// e.g. 'assets/sprites/1f_mysprite.png' has a message type of 0x1f. This message is used to key the messages in the frameside lua app
  Map<int, String> _filterSpriteAssets(List<String> files) {
    var spriteFiles = files
        .where((String pathFile) =>
            pathFile.startsWith('assets/sprites/') && pathFile.endsWith('.png'))
        .toList();

    // Create the map from hexadecimal integer prefix to sprite name
    final Map<int, String> spriteMap = {};

    for (final String sprite in spriteFiles) {
      // Extract the part of the filename without the directory and extension
      final String fileName =
          sprite.split('/').last; // e.g., "12_spriteone.png"

      // Extract the hexadecimal prefix and the sprite name
      final String hexPrefix = fileName.split('_').first; // e.g., "12"

      // Convert the hexadecimal prefix to an integer
      final int? hexValue = int.tryParse(hexPrefix, radix: 16);

      if (hexValue == null) {
        _log.severe('invalid hex prefix: $hexPrefix for asset $sprite');
      } else {
        // Add the hex value and sprite to the map
        spriteMap[hexValue] = sprite;
      }
    }

    return spriteMap;
  }

  /// Loops over each of the filtered sprites in the assets/sprites directory and sends each sprite with the message_type
  /// indicated as two hex digits in its filename, e.g. 'assets/sprites/1f_mysprite.png' has a message code of 0x1f
  /// Sprites should be PNGs with palettes of up to 2, 4, or 16 colors (1-, 2-, or 4-bit indexed palettes)
  /// Alpha channel (4th-RGBA), if present, is dropped before sending to Frame (RGB only, but color 0 is VOID)
  Future<void> _uploadSprites(Map<int, String> spriteMap) async {
    for (var entry in spriteMap.entries) {
      try {
        var sprite = TxSprite.fromPngBytes(
            pngBytes:
                Uint8List.sublistView(await rootBundle.load(entry.value)));

        // send sprite to Frame with its associated message type
        await frame!.sendMessage(entry.key, sprite.pack());
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        _log.severe('$e');
      }
    }
  }

  Future<void> showLoadingScreen() async {
    // TODO harmonize these APIs
    if (frame!.type == BrilliantDeviceType.halo) {
      await frame!.sendString(
          'frame.display.power_save(false);frame.display.clear();frame.display.text(\'Loading...\',100,127,0xFFFFFF);print(0)',
          awaitResponse: true);
    } else {
      await frame!.sendString(
          'frame.display.text(\'Loading...\',1,1);frame.display.show();print(0)',
          awaitResponse: true);
    }
  }

  /// Suitable for inclusion in initState or other startup code,
  /// this function will attempt connection, start app (loading Lua, sprites)
  /// and optionally call run() (unawaited)
  /// to save a few connect/start/(run) steps
  Future<void> tryScanAndConnectAndStart({required bool andRun}) async {
    if (currentState == ApplicationState.disconnected) {

      _log.fine('calling scanOrReconnectFrame');
      await scanOrReconnectFrame();

      if (currentState == ApplicationState.connected) {

        _log.fine('calling startApplication');
        await startApplication();

        if (currentState == ApplicationState.ready && andRun) {
          // don't await this one for run() functions that keep running a main loop, so initState() can complete
          _log.fine('calling run');
          run();
        }
        else {
          _log.fine('not ready or andRun is false - not calling run');
        }
      }
      else {
        // connection didn't succeed, decide what you want to do if the app starts and the user doesn't tap Frame to wake it up
        _log.fine('not connected - finishing start attempt');
      }
    }
    else {
      _log.fine('not in disconnected state - not attempting scan/connect');
    }
  }

  /// the SimpleFrameApp subclass implements application-specific code
  Future<void> run();

  /// the SimpleFrameApp subclass implements application-specific code
  Future<void> cancel();
}
