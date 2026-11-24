# Reusable prompt: let an AI build *and test* a game with no screen

Paste everything in the box below into a new session (Claude Code or a similar coding agent that can run
shell commands). Fill in the first line. It works best with **Godot**. The "Other engines" section at the
end covers Unity, web games and others.

---

```text
I want you to build/modify this game: <DESCRIBE THE GAME OR THE CHANGE>.

You are running on a machine with no monitor, no GPU and no mouse. Don't just write code and hope:
actually run the game, look at it, and fix what you see before you tell me it's done. Use this workflow.

1. GET THE REAL ENGINE
   - Download the official engine build into a scratch folder (for Godot: the Linux x86_64 .zip from
     github.com/godotengine/godot/releases, the version the project targets, e.g. 4.3-stable).
   - Don't install it system-wide and don't commit it.
   - Import the project once so class names and caches are built:
       godot --headless --path . --import

2. ADD DEV FLAGS TO THE GAME (read with OS.get_cmdline_user_args(), passed after `--`)
   - --fresh        ignore the save file
   - --autotest     play the game automatically: simulate taps/clicks, buy upgrades, and fast-forward
                    through every progression stage, printing one status line per stage
                    (e.g. "[autotest] stage=3 score=… entities=…"). It must quit when done.
   - --until=N      stop the autotest early (to capture mid-game states)
   - --shot=PATH    save a screenshot of the viewport and quit:
                      await RenderingServer.frame_post_draw
                      get_viewport().get_texture().get_image().save_png(PATH)
   - --shots=DIR    for cutscenes/timelines: save screenshots at a list of key timestamps, then quit
   - extra flags as needed to reach a state for a picture (e.g. --zoom=N, --shop to open a menu)
   - Keep the flags in the codebase and document them in the README. They are the project's test harness.

3. FAST LOGIC CHECK (no rendering)
       godot --headless --path . -- --fresh --autotest
   - Any "SCRIPT ERROR" or "Parse Error" must be fixed before going further.
   - Ignore errors that only come from the headless dummy renderer (e.g. mesh_get_surface_count).
   - To check a single file for syntax errors: --check-only --script res://path.gd
     (autoload names show as "not found" there; that's expected).

4. REAL RENDERING ON A VIRTUAL SCREEN
   Use Xvfb + Mesa software OpenGL and the Compatibility renderer:
       xvfb-run -a -s "-screen 0 WxHx24" godot --path . --rendering-driver opengl3 \
         --resolution WxH -- --fresh --shot=/tmp/out.png
   - Use the game's real target resolution (e.g. 720x1280 for portrait mobile).
   - Capture at least: the first screen, a mid-game state, the late/complete state, and each menu.
   - OPEN EVERY SCREENSHOT AND CRITIQUE IT like a picky art director: blown-out or muddy colours,
     things floating/clipping/misaligned, unreadable text, UI overlapping important action, icons that
     read as the wrong thing, objects off-screen, empty or noisy areas. Fix and re-shoot until it's good.
   - For many frames, combine them into one contact-sheet image (Pillow, or ffmpeg's tile filter)
     so you can review a whole sequence at once.

5. VIDEO + AUDIO (for cutscenes, animations, juice)
   - Record with Godot's Movie Maker (deterministic, includes audio):
       xvfb-run -a -s "-screen 0 WxHx24" godot --path . --rendering-driver opengl3 \
         --resolution WxH --write-movie /tmp/clip.avi --fixed-fps 30 --quit-after <frames> <scene>
       ffmpeg -i /tmp/clip.avi -c:v libx264 -pix_fmt yuv420p -crf 26 -c:a aac clip.mp4
   - Pull frames back out of the video and review them (ffmpeg select + tile).
   - You can't hear, so measure the audio: ffmpeg -af volumedetect (mean/max volume). For procedural audio,
     also render it offline in a test script, assert every sample is finite, and print peak/RMS per section.

6. FLOW AND SAVE CHECKS
   - Test scene transitions end to end (e.g. intro → skip → game). If an in-engine screenshot flag would
     change the flow, grab the virtual screen from outside with ImageMagick: import -window root out.png
   - Save → reload: run the game until it saves, launch it again, compare screenshots, and confirm the
     save file contains what it should.
   - Delete the test save file afterwards so it doesn't leak into the next run.

7. BEFORE EVERY COMMIT
   - Re-run the headless --autotest as a regression check and paste the last lines of output.
   - Regenerate the README screenshots so they match the current build.

8. BE HONEST ABOUT LIMITS
   When you report back, say what you verified (with the evidence) and what this setup CAN'T verify:
   real touch/feel, performance on a real phone/GPU (software rendering is slow and unrepresentative),
   and how it actually sounds. Tell me what to test by hand on a device.

Other rules:
- Prefer procedural/code-generated placeholder art and sound so the project runs straight after cloning,
  unless I give you assets.
- GDScript gotchas: avoid `:=` when the right-hand side is a Variant (dictionary values, untyped arrays);
  write multi-line lambdas as a local variable and pass that variable, rather than inlining them in a call;
  in the Compatibility renderer, set source_color shader uniforms from code (their defaults aren't converted
  to linear space).
- Show me the key screenshots (and the video, if any) when you finish.
```

---

## Other engines

Swap steps 1–5 for the equivalent tools. The idea stays the same: dev flags → headless logic run → render on
a virtual screen → look at the pictures → fix → repeat.

| Engine | Headless logic run | Screenshots / video on a virtual screen |
|---|---|---|
| **Unity** | `Unity -batchmode -nographics -executeMethod AutoTest.Run -quit` (or the Unity Test Framework in batch mode) | Build a Linux player and run it under `xvfb-run` with `-force-glcore`; capture with `ScreenCapture.CaptureScreenshot`, or record with the Recorder package |
| **Web (Phaser, Three.js, PixiJS, canvas)** | Node unit tests for the game logic | Playwright with headless Chromium: `page.screenshot()`, `page.video` recording, and `page.mouse.click()` for real input |
| **Unreal** | `UnrealEditor-Cmd ... -ExecCmds="Automation RunTests ..." -unattended -nullrhi` | Run packaged builds under Xvfb; `HighResShot` console command; Movie Render Queue |
| **Love2D / Pygame / Raylib** | Run with a `--autotest` flag and a dummy video driver (`SDL_VIDEODRIVER=dummy`) | Run under `xvfb-run` and save the framebuffer (`love.graphics.captureScreenshot`, `pygame.image.save`, `TakeScreenshot`) |

**Bonus for web games:** Playwright can do *real* clicks and drags, which gets closer to testing feel than
simulated input inside the engine.
