# Sound Files

Place your soothing `.caf` sound files here. They must be ≤ 30 seconds.

## Expected filenames

| Filename | Shown in app as |
|----------|-----------------|
| `gentle_chime.caf` | Gentle Chime |
| `soft_bell.caf` | Soft Bell |
| `morning_dew.caf` | Morning Dew |

## Converting audio to .caf

```sh
afconvert -f caff -d LEI16 your_sound.mp3 gentle_chime.caf
```

## Free sound sources (CC0 / royalty-free)

- https://freesound.org — search "gentle chime notification", "soft bell", "meditation bell"
- https://pixabay.com/sound-effects/ — search "chime" or "soft notification"
- https://mixkit.co/free-sound-effects/notification/ — CC0 notification sounds

If no .caf files are present, the app uses the system default notification sound.
