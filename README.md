<p align="center">
  <img src="yuuna/assets/meta/icon.png" width="160" height="160">
</p>
<h3 align="center">jidoujisho (fork)</h3>
<p align="center">A fork of <a href="https://github.com/arianneorpilla/jidoujisho">arianneorpilla/jidoujisho</a>, a full-featured immersion language learning suite for mobile, with an updated ebook reader and an e-ink mode.</p>

---

For what the app does, how to use it, supported formats and AnkiDroid setup, see the
**[original repository](https://github.com/arianneorpilla/jidoujisho)** and its
**[wiki](https://github.com/arianneorpilla/jidoujisho/wiki)**. Everything there applies
to this fork too, except for the changes below.

## What this fork changes

- **Native Mokuro reader.** A new **Mokuro (native)** source opens the `.mokuro` files
  written by [mokuro](https://github.com/kha-white/mokuro) 0.2 and shows the pages in
  the app itself instead of a WebView. Pages are read from the folder next to the file,
  or straight from a `.cbz` or `.zip` without extracting it.
  - Tap text to look up the word there; the whole speech bubble is the search text, and
    the sentence and page image go to the card creator.
  - One page at a time in portrait, two side by side in landscape, with an optional
    cover page. Swipe or tap the edges to turn pages, pinch to zoom up to 5×.
  - Long press a bubble, or turn on a setting, to draw the recognised text over the
    page. In vertical text, long vowel marks and brackets are turned sideways and runs
    like `！！` share one character's space, as in print.
  - History with covers that resumes on the last page read, and its own settings:
    reading direction, highlighting, inverted colours, text outlines for checking OCR,
    and volume button page turning (unreliable on some phones).

  The existing Mokuro source, which reads mokuro's legacy HTML output, is unchanged.
- **Updated ッツ Ebook Reader** to the current
  [upstream version](https://github.com/ttu-ttu/ebook-reader), bundled as a git
  submodule (see [`yuuna/tool/ttu/README.md`](yuuna/tool/ttu/README.md)). Existing
  libraries, progress and reader settings carry over.
- **E-ink mode** for black-and-white e-readers, enabled from the home screen menu: a
  pure black-and-white theme without animations, an opaque dictionary pop-up with
  slightly larger text, and black-and-white themes for the ebook reader and the native
  Mokuro reader.
- **Fewer crashes.** When Android kills a WebView's renderer, for example under memory
  pressure on e-readers, the reader reloads on the page it showed instead of the whole
  app closing. AnkiDroid errors no longer close the app, and the AnkiDroid duplicate
  check runs off the main thread so a slow AnkiDroid can't freeze lookups.
- **Diagnostics.** After an unexpected exit, the next start shows the reason Android
  recorded (crash, freeze, low memory...) with a Copy button (Android 11 and later). The
  home screen menu can copy a log of recent reader lookups, for tracking down pop-ups
  that close on their own.
- **Tapping the source name bar** opens the source picker.
- **Installs as a separate app**, "jidoujisho+", so it doesn't replace the original.

## Downloads

Signed APKs for arm64 phones are on the
[Releases](https://github.com/mkozden/jidoujisho/releases) page. Each release installs
over the previous one.

## Building

The **Build Android APK** workflow builds the APK for every push and attaches it to the
run as the `jidoujisho-apk` artifact. To build locally:

```sh
cd yuuna
flutter pub get
flutter build apk --target-platform=android-arm64
```

- **Signing.** CI signs with the key in the `SIGNING_KEYSTORE` (a base64-encoded PKCS12
  keystore holding the key `jidoujisho`) and `SIGNING_PASSWORD` secrets, so each build
  installs over the last. Without them it uses a random debug key. Locally, put the
  keystore details in `yuuna/android/key.properties`.
- **Dev build.** Building with `yuunaDev=true` (in `yuuna/android/gradle.properties`, or
  `ORG_GRADLE_PROJECT_yuunaDev=true`) makes "jidoujisho dev", a third app with its own
  data, for trying a feature branch next to an everyday install. CI always builds `main`
  without it.
- **Releases.** Bump `version` in [`yuuna/pubspec.yaml`](yuuna/pubspec.yaml), merge to
  `main`, then run the **Release** workflow from the Actions tab. It builds a signed APK
  from `main`, tags the commit `v<version>` and publishes a release with the APK and
  notes generated from the merged pull requests. It stops if that version was already
  released or the signing secrets are missing.

## Contribution and attribution

All credit for jidoujisho goes to [arianneorpilla](https://github.com/arianneorpilla)
and the contributors of the original project:

<!-- readme: contributors -start -->
<table>
<tr>
    <td align="center">
        <a href="https://github.com/arianneorpilla">
            <img src="https://avatars.githubusercontent.com/u/11363922?v=4" width="100;" alt="arianneorpilla"/>
            <br />
            <sub><b>arianneorpilla</b></sub>
        </a>
    </td>
    <td align="center">
        <a href="https://github.com/m-edlund">
            <img src="https://avatars.githubusercontent.com/u/44649263?v=4" width="100;" alt="m-edlund"/>
            <br />
            <sub><b>m-edlund</b></sub>
        </a>
    </td>
    <td align="center">
        <a href="https://github.com/chrispavs">
            <img src="https://avatars.githubusercontent.com/u/21095600?v=4" width="100;" alt="chrispavs"/>
            <br />
            <sub><b>chrispavs</b></sub>
        </a>
    </td>
    <td align="center">
        <a href="https://github.com/Aegyo">
            <img src="https://avatars.githubusercontent.com/u/4183969?v=4" width="100;" alt="Aegyo"/>
            <br />
            <sub><b>Aegyo</b></sub>
        </a>
    </td>
    <td align="center">
        <a href="https://github.com/Aquafina-water-bottle">
            <img src="https://avatars.githubusercontent.com/u/17107540?v=4" width="100;" alt="Aquafina-water-bottle"/>
            <br />
            <sub><b>Aquafina-water-bottle</b></sub>
        </a>
    </td>
    <td align="center">
        <a href="https://github.com/Natsume-197">
            <img src="https://avatars.githubusercontent.com/u/36428207?v=4" width="100;" alt="Natsume-197"/>
            <br />
            <sub><b>Natsume-197</b></sub>
        </a>
    </td></tr>
<tr>
    <td align="center">
        <a href="https://github.com/MarvNC">
            <img src="https://avatars.githubusercontent.com/u/17340496?v=4" width="100;" alt="MarvNC"/>
            <br />
            <sub><b>MarvNC</b></sub>
        </a>
    </td>
    <td align="center">
        <a href="https://github.com/TheAtlasRises">
            <img src="https://avatars.githubusercontent.com/u/106642434?v=4" width="100;" alt="TheAtlasRises"/>
            <br />
            <sub><b>TheAtlasRises</b></sub>
        </a>
    </td></tr>
</table>
<!-- readme: contributors -end -->

jidoujisho is written in [Dart](https://dart.dev/) with [Flutter](https://flutter.dev/)
and is available under the [GNU General Public License v3.0](LICENSE); so is this fork.
The ebook reader is [ッツ Ebook Reader](https://github.com/ttu-ttu/ebook-reader)
(BSD-3-Clause). See the original repository for the full list of libraries and services
the app builds on. The app logo is by [suzy](https://88suzysuzy.carrd.co/) and
[Aaron Marbella](https://www.buymeacoffee.com/marblesaa).
