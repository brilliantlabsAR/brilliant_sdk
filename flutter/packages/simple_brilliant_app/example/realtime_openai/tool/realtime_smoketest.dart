// Throwaway protocol smoke-test for the OpenAI Realtime GA wire protocol,
// exercising the same web_socket_channel/IOWebSocketChannel path as
// lib/openai_realtime.dart. Validates: header auth, session.update acceptance,
// and the server event names the client depends on. Elicits a response from a
// text turn (no mic audio / no Halo needed).
//
// Run: OPENAI_API_KEY=$(cat <keyfile>) dart run tool/realtime_smoketest.dart
// The key is read from the environment and never printed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('OPENAI_API_KEY not set');
    exit(2);
  }
  const endpoint = 'wss://api.openai.com/v1/realtime?model=gpt-realtime';
  // OpenAI GA requires the pcm rate >= 24000 (16000 is rejected with
  // integer_below_min_value); a 16kHz backend must be a local one.
  final rate = int.tryParse(Platform.environment['RATE'] ?? '24000') ?? 24000;
  print('testing sample rate: $rate');

  final channel = IOWebSocketChannel.connect(
    Uri.parse(endpoint),
    headers: {
      // GA API: no OpenAI-Beta header
      'Authorization': 'Bearer $apiKey',
    },
  );
  await channel.ready;
  print('websocket connected');

  final seen = <String, int>{};
  var audioDeltaBytes = 0;
  final outputTranscript = StringBuffer();
  final done = Completer<void>();

  channel.stream.listen((message) {
    final event =
        jsonDecode(message is String ? message : utf8.decode(message));
    final type = event['type'] as String? ?? '(no type)';
    seen[type] = (seen[type] ?? 0) + 1;

    switch (type) {
      case 'response.output_audio.delta':
        final d = event['delta'] as String?;
        if (d != null) audioDeltaBytes += base64Decode(d).length;
        break;
      case 'response.output_audio_transcript.delta':
        outputTranscript.write(event['delta'] ?? '');
        break;
      case 'error':
        print('ERROR event: ${event['error']}');
        break;
      case 'response.done':
        if (!done.isCompleted) done.complete();
        break;
    }
  }, onError: (e) {
    print('stream error: $e');
    if (!done.isCompleted) done.completeError(e);
  }, onDone: () {
    if (!done.isCompleted) done.complete();
  });

  // GA session config
  channel.sink.add(jsonEncode({
    'type': 'session.update',
    'session': {
      'type': 'realtime',
      'output_modalities': ['audio'],
      'instructions': 'You are a test. Answer in three words.',
      'audio': {
        'input': {
          'format': {'type': 'audio/pcm', 'rate': rate},
          'transcription': {'model': 'whisper-1'},
          'turn_detection': {'type': 'server_vad'},
        },
        'output': {
          'format': {'type': 'audio/pcm', 'rate': rate},
          'voice': 'alloy',
        },
      },
    }
  }));

  // give the session a moment, then elicit an audio response from a text turn
  await Future.delayed(const Duration(milliseconds: 500));
  channel.sink.add(jsonEncode({
    'type': 'conversation.item.create',
    'item': {
      'type': 'message',
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': 'Say a three word greeting.'}
      ],
    }
  }));
  channel.sink.add(jsonEncode({'type': 'response.create'}));

  await done.future.timeout(const Duration(seconds: 20), onTimeout: () {
    print('TIMEOUT waiting for response.done');
  });
  await channel.sink.close();

  print('\n=== event types seen ===');
  final keys = seen.keys.toList()..sort();
  for (final k in keys) {
    print('  ${seen[k].toString().padLeft(3)}  $k');
  }
  print('\naudio delta bytes: $audioDeltaBytes');
  print('output transcript: "${outputTranscript.toString().trim()}"');

  // assert the GA event names lib/openai_realtime.dart relies on
  const required = [
    'response.output_audio.delta',
    'response.output_audio_transcript.delta',
    'response.done',
  ];
  final missing = required.where((r) => !seen.containsKey(r)).toList();
  final gotSession = seen.containsKey('session.created') ||
      seen.containsKey('session.updated');
  print('\nsession.created/updated seen: $gotSession');
  if (missing.isEmpty && gotSession && audioDeltaBytes > 0) {
    print('RESULT: PASS - client event names match');
  } else {
    print('RESULT: FAIL - missing: $missing (audioBytes=$audioDeltaBytes)');
    exit(1);
  }
}
