import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:brilliant_msg/tx_msg.dart';

final _log = Logger("TxSfxr");

/// A message containing sfxr sound effect parameters.
/// Can be initialized with defaults, specific values, or loaded from JSON.
class TxSfxr extends TxMsg {
  // Header
  int waveType;
  double soundVol;

  // Frequency
  double pBaseFreq;
  double pFreqLimit;
  double pFreqRamp;
  double pFreqDramp;

  // Duty Cycle
  double pDuty;
  double pDutyRamp;

  // Vibrato
  double pVibStrength;
  double pVibSpeed;
  double pVibDelay;

  // Envelope
  double pEnvAttack;
  double pEnvSustain;
  double pEnvDecay;
  double pEnvPunch;

  // Lowpass Filter
  double pLpfResonance;
  double pLpfFreq;
  double pLpfRamp;

  // Highpass Filter
  double pHpfFreq;
  double pHpfRamp;

  // Phaser
  double pPhaOffset;
  double pPhaRamp;

  // Repeat Speed
  double pRepeatSpeed;

  // Arpeggio / Change
  double pArpSpeed;
  double pArpMod;

  TxSfxr({
    this.waveType = 0,
    this.soundVol = 0.5,
    this.pBaseFreq = 0.3,
    this.pFreqLimit = 0.0,
    this.pFreqRamp = 0.0,
    this.pFreqDramp = 0.0,
    this.pDuty = 0.0,
    this.pDutyRamp = 0.0,
    this.pVibStrength = 0.0,
    this.pVibSpeed = 0.0,
    this.pVibDelay = 0.0,
    this.pEnvAttack = 0.0,
    this.pEnvSustain = 0.3,
    this.pEnvDecay = 0.4,
    this.pEnvPunch = 0.0,
    this.pLpfResonance = 0.0,
    this.pLpfFreq = 1.0,
    this.pLpfRamp = 0.0,
    this.pHpfFreq = 0.0,
    this.pHpfRamp = 0.0,
    this.pPhaOffset = 0.0,
    this.pPhaRamp = 0.0,
    this.pRepeatSpeed = 0.0,
    this.pArpSpeed = 0.0,
    this.pArpMod = 0.0,
  });

  /// Create a TxSfxr instance from a JSON string or Map.
  /// Only fields matching the class definition are imported.
  factory TxSfxr.fromJson(dynamic jsonInput) {
    Map<String, dynamic> data;
    if (jsonInput is String) {
      data = jsonDecode(jsonInput);
    } else if (jsonInput is Map<String, dynamic>) {
      data = jsonInput;
    } else {
      throw const FormatException("Invalid JSON input for TxSfxr");
    }

    // Helper to safely get double or int values and convert to double
    double? getDouble(String key) {
      var val = data[key];
      if (val is num) return val.toDouble();
      return null;
    }

    // Helper to safely get int
    int? getInt(String key) {
      var val = data[key];
      if (val is num) return val.toInt();
      return null;
    }

    return TxSfxr(
      waveType: getInt('wave_type') ?? 0,
      soundVol: getDouble('sound_vol') ?? 0.5,
      pBaseFreq: getDouble('p_base_freq') ?? 0.3,
      pFreqLimit: getDouble('p_freq_limit') ?? 0.0,
      pFreqRamp: getDouble('p_freq_ramp') ?? 0.0,
      pFreqDramp: getDouble('p_freq_dramp') ?? 0.0,
      pDuty: getDouble('p_duty') ?? 0.0,
      pDutyRamp: getDouble('p_duty_ramp') ?? 0.0,
      pVibStrength: getDouble('p_vib_strength') ?? 0.0,
      pVibSpeed: getDouble('p_vib_speed') ?? 0.0,
      pVibDelay: getDouble('p_vib_delay') ?? 0.0,
      pEnvAttack: getDouble('p_env_attack') ?? 0.0,
      pEnvSustain: getDouble('p_env_sustain') ?? 0.3,
      pEnvDecay: getDouble('p_env_decay') ?? 0.4,
      pEnvPunch: getDouble('p_env_punch') ?? 0.0,
      pLpfResonance: getDouble('p_lpf_resonance') ?? 0.0,
      pLpfFreq: getDouble('p_lpf_freq') ?? 1.0,
      pLpfRamp: getDouble('p_lpf_ramp') ?? 0.0,
      pHpfFreq: getDouble('p_hpf_freq') ?? 0.0,
      pHpfRamp: getDouble('p_hpf_ramp') ?? 0.0,
      pPhaOffset: getDouble('p_pha_offset') ?? 0.0,
      pPhaRamp: getDouble('p_pha_ramp') ?? 0.0,
      pRepeatSpeed: getDouble('p_repeat_speed') ?? 0.0,
      pArpSpeed: getDouble('p_arp_speed') ?? 0.0,
      pArpMod: getDouble('p_arp_mod') ?? 0.0,
    );
  }

  /// Packs the current parameters into a binary object compatible 
  /// with the Lua sfxr deserializer (Version 102).
  @override
  Uint8List pack() {
    const int version = 102;
    
    // Calculate total size: 
    // 2 ints (4 bytes each) + 24 floats (4 bytes each) + 1 padding byte
    // 8 + 96 + 1 = 105 bytes
    final ByteData b = ByteData(105);
    int offset = 0;

    void packInt(int val) {
      b.setInt32(offset, val, Endian.little);
      offset += 4;
    }

    void packFloat(double val) {
      b.setFloat32(offset, val, Endian.little);
      offset += 4;
    }

    // --- Header ---
    packInt(version);
    packInt(waveType);

    // --- Volume ---
    packFloat(soundVol);

    // --- Frequency ---
    packFloat(pBaseFreq);
    packFloat(pFreqLimit);
    packFloat(pFreqRamp);
    packFloat(pFreqDramp);

    // --- Duty Cycle ---
    packFloat(pDuty);
    packFloat(pDutyRamp);

    // --- Vibrato ---
    packFloat(pVibStrength);
    packFloat(pVibSpeed);
    packFloat(pVibDelay);

    // --- Envelope ---
    packFloat(pEnvAttack);
    packFloat(pEnvSustain);
    packFloat(pEnvDecay);
    packFloat(pEnvPunch);

    // --- Filter Flag ---
    // 1 byte padding (corresponds to 'filter_on' bool in C++)
    b.setUint8(offset, 0);
    offset += 1;

    // --- Lowpass Filter ---
    packFloat(pLpfResonance);
    packFloat(pLpfFreq);
    packFloat(pLpfRamp);

    // --- Highpass Filter ---
    packFloat(pHpfFreq);
    packFloat(pHpfRamp);

    // --- Phaser ---
    packFloat(pPhaOffset);
    packFloat(pPhaRamp);

    // --- Repeat Speed ---
    packFloat(pRepeatSpeed);

    // --- Arpeggio / Change ---
    packFloat(pArpSpeed);
    packFloat(pArpMod);

    _log.fine(() => 'Packed SFXR: $offset bytes');
    return b.buffer.asUint8List();
  }
}