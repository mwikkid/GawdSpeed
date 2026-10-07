# The guide

`guide.html` is the source. `scripts/make-guide.sh` prints it to `GawdSpeed-Guide.pdf`
(headless Chrome); the PDF is committed, bundled in the app and copied into the DMG's
Docs folder. Re-run it after changing the controls, and re-check the numbered pins.

`window.png` is the app at its 900 × 490 design size (a 1800 × 980 capture) showing a
generated demo song. To retake it:

1. Make the demo song (Homebrew ffmpeg, which has `lavfi`; the bundled one doesn't):

   ```bash
   ffmpeg -y -f lavfi -i "aevalsrc='0.9*exp(-18*mod(t\,0.5))*sin(2*PI*55*t*(1+exp(-30*mod(t\,0.5))))':d=200" \
     -f lavfi -i "aevalsrc='0.25*(1+0.6*sin(2*PI*0.05*t))*exp(-3*mod(t\,2))*(sin(2*PI*220*t)+0.6*sin(2*PI*277.2*t)+0.5*sin(2*PI*329.6*t))':d=200" \
     -f lavfi -i "anoisesrc=d=200:c=white:a=0.5,highpass=f=6000,volume='0.6*exp(-60*mod(t,0.25))':eval=frame" \
     -filter_complex "[0][1][2]amix=inputs=3:normalize=0,volume='0.6+0.4*sin(2*PI*t/45)':eval=frame,aformat=channel_layouts=stereo" \
     -c:a pcm_s16le -metadata title="Demo Song" -metadata artist="GawdSpeed" "Demo Song.wav"
   ```

2. Before opening it, write its session (speed 75%, +2 st, loop 1:01–1:09, both filters
   turned, three regions) to `~/Library/Application Support/GawdSpeed/Sessions/<fingerprint>.json`.
   The fingerprint is `FileFingerprint` in `Sources/Analysis/PeakPyramid.swift`.
3. Open it, press Space twice so the window is active, and capture the window
   (`screencapture -l <window id>`).
