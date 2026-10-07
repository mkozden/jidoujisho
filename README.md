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

- **Updated ッツ Ebook Reader.** The bundled reader is upgraded from an April 2023
  build to [ttu-ttu/ebook-reader](https://github.com/ttu-ttu/ebook-reader) `301aef49`
  (September 2026). This brings custom themes, reading statistics, and a fix for
  bookmarks drifting off the page start after rotating the screen or resizing the
  reader. Existing libraries, progress and reader settings carry over. The reader is
  pinned as a git submodule and rebuilt with a script; see
  [`yuuna/tool/ttu/README.md`](yuuna/tool/ttu/README.md).
- **E-ink mode** for black-and-white e-readers. Turn it on from the home screen menu.
  It switches to a pure black-and-white theme, removes animations, and uses static
  loading indicators. It also makes the dictionary pop-up opaque, with slightly larger
  text, and shows "already in Anki" by inverting the button instead of turning it red.
  In the ebook reader it adds black-and-white "E-ink" themes, since the default theme
  draws text in grey. Details:
  [`analysis/eink_qol_improvements.md`](analysis/eink_qol_improvements.md).
- **Installs alongside the original app** as "jidoujisho+"
  (`app.arianneorpilla.yuuna.plus`) with its own data. Release builds are signed with
  the build machine's debug key, so they cannot update an install signed elsewhere. To
  build the original package name instead, set `yuunaSideBySide=false` in
  `yuuna/android/gradle.properties`.
- **Smaller APK.** Only the native libraries for the targeted CPU architectures are
  packaged. The arm64 APK is about 200 MB instead of about 470 MB.
- **Analysis reports** in [`analysis/`](analysis): e-ink improvements, and the
  feasibility of a built-in Mokuro (`.mokuro`) reader.

## Building

The APK is built by the GitHub Actions workflow (Flutter 3.13.5, JDK 11) and attached
to each run as the `jidoujisho-apk` artifact. To build locally:

```sh
cd yuuna
flutter pub get
flutter build apk --target-platform=android-arm64
```

Build the original package name without editing files:

```sh
env ORG_GRADLE_PROJECT_yuunaSideBySide=false flutter build apk --target-platform=android-arm64
```

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
