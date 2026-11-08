# FotoTag

**English** · [Italiano](README.it.md)

**Automatic keywords and captions for your photo archive, generated entirely on your Mac.**

FotoTag looks at your photos and suggests keywords and a short caption for each one. You review the suggestions, and FotoTag writes the ones you approve into the image files, or into an `.xmp` sidecar for RAW files. After that, you can find any photo by describing it: "kids at the beach", "fog on the hills", "bike in the rain".

It's built for photographers with large archives, including film scans, whether they live on an external drive, a NAS or a cloud folder. Nothing is uploaded: the AI models run locally on Apple silicon.

![Reviewing suggested keywords and caption for a photo](docs/immagini/review.png)

| Search by description | Profiles turn folder names into keywords |
|---|---|
| ![Searching for "fog on the hills"](docs/immagini/search.png) | ![Testing a profile on a folder path](docs/immagini/profiles.png) |

## Features

- **Private by design.** A vision-language model (Qwen3-VL, running on [MLX](https://github.com/ml-explore/mlx-swift)) analyzes your photos on your Mac. No cloud service, no account, no subscription.
- **You stay in control.** Nothing is written until you approve it.
- **Safe writes.** Metadata is added without re-encoding the image, and FotoTag keeps a backup of every file it changes. RAW files are never modified; their keywords go into the `.xmp` sidecar.
- **Search by description.** A second model (SigLIP 2) lets you search in plain language, even among photos you haven't tagged yet.
- **Understands how you organize.** Profiles read your folder structure (year/month/roll, folder names worth keeping as keywords, film stock codes like "hp5" → "Ilford HP5 Plus 400").
- **English or Italian.** The interface follows your Mac's language, and keywords can be written in either language.

## Requirements

- A Mac with Apple silicon (M1 or later) running macOS 14 Sonoma or later
- 16 GB of memory for the standard model (Qwen3-VL 8B, a 5.8 GB download). On Macs with less memory FotoTag suggests a smaller 4B model (3.1 GB, needs at least 8 GB): about twice as fast, but less accurate.
- About 20 GB of free disk space: 5 GB for the build, 5.8 GB for the analysis model (3.1 GB for the small one), 1.5 GB for the search model, plus thumbnails. Before downloading a model, FotoTag checks that at least 2 GB would still be free afterwards.
- Xcode 26 or later (free on the Mac App Store)

## Installation

FotoTag isn't distributed as a ready-made app. You build it from source with one command, which takes a few minutes. Since the app isn't signed with an Apple Developer certificate, building it yourself also avoids macOS's "unidentified developer" warnings.

1. Install Xcode and open it once so it can finish setting up.
2. Install the Metal toolchain, which Xcode doesn't include by default:
   ```
   xcodebuild -downloadComponent MetalToolchain
   ```
3. Clone the repository and build:
   ```
   git clone https://github.com/f-loren/FotoTagMac.git
   cd FotoTagMac
   ./crea_app.sh
   ```
   The script builds FotoTag, copies it to your Applications folder and launches it. Build files go to `../_build`, next to the repository; set `FOTOTAG_BUILD=/some/path` to put them somewhere else.

To update, run `git pull` and `./crea_app.sh` again. If FotoTag is running, the script quits it first, which stops any analysis in progress.

## Getting started

1. **Give FotoTag access to your photos.** Choose the folder or drive that holds them. FotoTag lists every subfolder containing photos (RAW, HEIC, JPEG, TIFF). It analyzes JPEG, HEIC and TIFF files. RAW files aren't analyzed directly: when FotoTag can reliably match a RAW to the JPEG of the same shot (or you pair them yourself), the RAW's sidecar gets the JPEG's keywords.
2. **Allow macOS access** to Desktop, Documents or Downloads if asked. Because the app is unsigned, macOS asks again after every build.
3. **Pick a keyword language.** Keywords are in Italian by default; switch to English in Settings ▸ General ▸ Tag Language.
4. **Analyze a folder.** Click **Analyze**. The first time, FotoTag offers to download the model that suits your Mac (once, from Hugging Face). Expect around 8–10 seconds per photo with the standard model.
5. **Review and write.** Check the suggestions in **To Review**, approve them, and click **Write to Files** whenever you're ready. Backups are kept for 5 days; you can turn them off in Settings ▸ General.
6. **Search.** The first time you search, FotoTag offers to download the search model (SigLIP 2, 0.75 GB).

## Profiles

A profile tells FotoTag how to interpret your folder names: whether a folder name becomes a keyword, whether your folders follow a year/month/roll structure, which names to ignore ("export", "jpg"…), which ones mean a film scan, and how to expand film stock codes. You assign a profile to each drive or folder in Settings ▸ General and edit it in Settings ▸ Profiles, where you can paste a path and see the keywords it would produce.

The **Generic** profile is a good starting point. Profiles can be shared as JSON files (Import from a File… / Export to a File… in the profile's "…" menu); `profili/esempio-pellicola.json` is an example for a film archive organized by year, month and roll.

## Privacy and data

- Your photos never leave your Mac. The only network access is downloading the models from Hugging Face.
- Everything FotoTag stores (database, profiles, models, thumbnails, backups and a log) lives in `~/Library/Application Support/FotoTag/`.
- Your photos stay where they are. FotoTag only changes them when you click **Write to Files** and confirm.

## FAQ

**Why isn't there a download?** Shipping a pre-built app that macOS opens without warnings requires a paid Apple Developer account. Building from source is free and gives you exactly the same app.

**Which languages does it support?** English and Italian, for both the interface and the keywords. The interface follows your Mac's language; on a Mac set to another language without English in its preferred languages, it appears in Italian. Photos you've already analyzed keep their keywords in the original language until you analyze them again.

**Does it work with Lightroom, Photomator or darktable?** FotoTag writes keywords to standard XMP fields (`dc:subject`, plus Lightroom-style hierarchical keywords) and the caption to XMP and IPTC. For RAW files you can choose the sidecar naming used by Lightroom (`DSC_1234.xmp`, the default) or darktable (`DSC_1234.NEF.xmp`). When FotoTag updates an existing sidecar, it changes only the keywords and caption; everything else, including darktable's edit history, is preserved exactly. These are standard fields that Lightroom, Photomator and darktable read, but FotoTag hasn't been tested in each of them yet. If you use it with one of them, please open an issue and tell us how it went.

**Does it run on Intel Macs?** No. MLX requires Apple silicon.

## Contributing

Bug reports and ideas are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). To report a security issue, see [SECURITY.md](SECURITY.md).

For developers:
- `Sources/FotoTagCore`: analysis (MLX), database, fixed keywords and profiles, metadata writing, search. `Sources/FotoTag`: the SwiftUI app. `Sources/fototag-cli`: command-line test tools.
- Run the tests with `swift test --scratch-path ../_build/spm` (requires the Metal toolchain).
- What the app should do and why: [docs/SPEC.md](docs/SPEC.md) and the decision log in [docs/INTENZIONI.md](docs/INTENZIONI.md). Both are in Italian, as are the code comments.

## License

FotoTag is free software, released under the GNU General Public License v3. See [NOTICE.md](NOTICE.md) and the full text in [LICENSE](LICENSE).

The models are not included in this repository; FotoTag downloads them from Hugging Face. Qwen3-VL (Alibaba Cloud) and SigLIP 2 (Google) are both licensed under Apache 2.0. Third-party libraries and models are credited in [Risorse/RICONOSCIMENTI.md](Risorse/RICONOSCIMENTI.md).

Photos in the screenshots are public domain or CC0 images from Wikimedia Commons; see [docs/immagini/CREDITS.md](docs/immagini/CREDITS.md).
