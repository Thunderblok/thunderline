# Resurrection (rhythmic healing)

- **Checkpoint at gate**: store KV digest, RNG export, φ, ρ, affect/mood, J/D, Daisy snapshot, echo window.
- **SafeClose**: on terminate, request boundary close; write `resurrection_marker` (pending=true).
- **Resurrector**: on boot, if pending, restore Daisy + PLL + echo; log `resumed`; clear pending.
