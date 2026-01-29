import struct
import json
from dataclasses import dataclass

@dataclass
class TxSfxr:
    """
    A message containing sfxr sound effect parameters.
    Can be initialized with defaults, specific values, or loaded from JSON.
    """
    # Header
    wave_type: int = 0
    sound_vol: float = 0.5

    # Frequency
    p_base_freq: float = 0.3
    p_freq_limit: float = 0.0
    p_freq_ramp: float = 0.0
    p_freq_dramp: float = 0.0

    # Duty Cycle
    p_duty: float = 0.0
    p_duty_ramp: float = 0.0

    # Vibrato
    p_vib_strength: float = 0.0
    p_vib_speed: float = 0.0
    p_vib_delay: float = 0.0

    # Envelope
    p_env_attack: float = 0.0
    p_env_sustain: float = 0.3
    p_env_decay: float = 0.4
    p_env_punch: float = 0.0

    # Lowpass Filter
    p_lpf_resonance: float = 0.0
    p_lpf_freq: float = 1.0
    p_lpf_ramp: float = 0.0

    # Highpass Filter
    p_hpf_freq: float = 0.0
    p_hpf_ramp: float = 0.0

    # Phaser
    p_pha_offset: float = 0.0
    p_pha_ramp: float = 0.0

    # Repeat Speed
    p_repeat_speed: float = 0.0

    # Arpeggio / Change
    p_arp_speed: float = 0.0
    p_arp_mod: float = 0.0

    def pack(self) -> bytes:
        """
        Packs the current parameters into a binary object compatible 
        with the Lua sfxr deserializer (Version 102).
        """
        version = 102
        b = bytearray()
        
        # --- Helpers ---
        def pack_int(val): return struct.pack('<i', int(val))
        def pack_float(val): return struct.pack('<f', float(val))

        # --- Header ---
        b.extend(pack_int(version))
        b.extend(pack_int(self.wave_type))

        # --- Volume ---
        b.extend(pack_float(self.sound_vol))

        # --- Frequency ---
        b.extend(pack_float(self.p_base_freq))
        b.extend(pack_float(self.p_freq_limit))
        b.extend(pack_float(self.p_freq_ramp))
        b.extend(pack_float(self.p_freq_dramp))

        # --- Duty Cycle ---
        b.extend(pack_float(self.p_duty))
        b.extend(pack_float(self.p_duty_ramp))

        # --- Vibrato ---
        b.extend(pack_float(self.p_vib_strength))
        b.extend(pack_float(self.p_vib_speed))
        b.extend(pack_float(self.p_vib_delay))

        # --- Envelope ---
        b.extend(pack_float(self.p_env_attack))
        b.extend(pack_float(self.p_env_sustain))
        b.extend(pack_float(self.p_env_decay))
        b.extend(pack_float(self.p_env_punch))

        # --- Filter Flag ---
        # 1 byte padding (corresponds to 'filter_on' bool in C++)
        b.extend(struct.pack('B', 0)) 

        # --- Lowpass Filter ---
        b.extend(pack_float(self.p_lpf_resonance))
        b.extend(pack_float(self.p_lpf_freq))
        b.extend(pack_float(self.p_lpf_ramp))

        # --- Highpass Filter ---
        b.extend(pack_float(self.p_hpf_freq))
        b.extend(pack_float(self.p_hpf_ramp))

        # --- Phaser ---
        b.extend(pack_float(self.p_pha_offset))
        b.extend(pack_float(self.p_pha_ramp))

        # --- Repeat Speed ---
        b.extend(pack_float(self.p_repeat_speed))

        # --- Arpeggio / Change ---
        b.extend(pack_float(self.p_arp_speed))
        b.extend(pack_float(self.p_arp_mod))

        return bytes(b)

    @classmethod
    def from_json(cls, json_input):
        """
        Create a TxSfxr instance from a JSON string or dictionary.
        Only fields matching the class definition are imported.
        """
        if isinstance(json_input, str):
            data = json.loads(json_input)
        else:
            data = json_input

        # Get the set of valid field names for this dataclass
        valid_keys = cls.__dataclass_fields__.keys()
        
        # Filter the input dictionary to only include valid keys
        # This prevents TypeError if the JSON has extra fields (like 'oldParams')
        filtered_data = {k: v for k, v in data.items() if k in valid_keys}
        
        return cls(**filtered_data)


# --- Usage Example ---
if __name__ == "__main__":
    
    # 1. Instantiate with specific params
    sfx1 = TxSfxr(p_base_freq=0.8, wave_type=2)
    sfx1.sound_vol = 0.6 # Mutable
    print(f"Manual Instance: Packed {len(sfx1.pack())} bytes.")

    # 2. Instantiate from JSON String
    json_str = """
    {
        "wave_type": 1,
        "p_base_freq": 0.746,
        "p_env_sustain": 0.077,
        "p_env_decay": 0.424,
        "p_lpf_freq": 1,
        "sound_vol": 0.25,
        "garbage_key": "ignore_me" 
    }
    """
    sfx2 = TxSfxr.from_json(json_str)
    
    # Verify mutation works
    sfx2.p_arp_speed = 0.5 
    
    binary_data = sfx2.pack()
    print(f"JSON Instance: Packed {len(binary_data)} bytes.")