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

- **Updated ッツ Ebook Reader** to the current
  [upstream version](https://github.com/ttu-ttu/ebook-reader), bundled as a git
  submodule (see [`yuuna/tool/ttu/README.md`](yuuna/tool/ttu/README.md)). Existing
  libraries, progress and reader settings carry over.
- **E-ink mode** for black-and-white e-readers, enabled from the home screen menu: a
  pure black-and-white theme without animations, an opaque dictionary pop-up with
  slightly larger text, and black-and-white themes for the ebook reader.
- **Installs as a separate app**, "jidoujisho+", so it doesn't replace the original.

## Building

The GitHub Actions workflow builds the APK and attaches it to each run as the
`jidoujisho-apk` artifact. To build locally:

```sh
cd yuuna
flutter pub get
flutter build apk --target-platform=android-arm64
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
