#!/bin/zsh
# Compila FotoTag e crea FotoTag.app (fuori dalla cartella sincronizzata), poi la apre.
# Uso: ./crea_app.sh            compila e apre
#      ./crea_app.sh --no-apri  compila soltanto
set -e
cd "${0:A:h}"
# cartella di build: sul disco esterno, accanto al progetto (il disco interno si riempie); FOTOTAG_BUILD=… per cambiarla
BUILD=${FOTOTAG_BUILD:-${0:A:h}/../_build}
mkdir -p $BUILD
PROD=$BUILD/Build/Products/Release
APP=$BUILD/FotoTag.app
echo "Compilo…"
xcodebuild -scheme FotoTag -configuration Release -destination 'platform=macOS' \
  -derivedDataPath $BUILD -skipMacroValidation build > $BUILD/build-app.log 2>&1 \
  || { grep -E "error:" $BUILD/build-app.log | sort -u | head -20; exit 1; }
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $PROD/FotoTag $APP/Contents/MacOS/
cp -R $PROD/*.bundle $APP/Contents/Resources/
# testi tradotti (D68): Bundle.main li cerca nelle .lproj dell'app, non nel bundle della risorsa
find $PROD/FotoTagMac_FotoTag.bundle -name "*.lproj" -maxdepth 3 -exec cp -R {} $APP/Contents/Resources/ \;
cp Risorse/FotoTag.icns $APP/Contents/Resources/   # icona (da Risorse/FotoTag.svg)
cp Risorse/RICONOSCIMENTI.md NOTICE.md LICENSE $APP/Contents/Resources/   # licenze (strumenti/raccogli_licenze.py)
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FotoTag</string>
  <key>CFBundleDisplayName</key><string>FotoTag</string>
  <key>CFBundleIdentifier</key><string>it.lorenzozanna.fototag</string>
  <key>CFBundleExecutable</key><string>FotoTag</string>
  <key>CFBundleIconFile</key><string>FotoTag</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 1)</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleDevelopmentRegion</key><string>it</string>
  <key>CFBundleLocalizations</key><array><string>it</string><string>en</string></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Lorenzo Zanna. Software libero, licenza GPL 3.0.</string>
</dict></plist>
PLIST
codesign --force --deep -s - $APP > /dev/null 2>&1
# copia in Applicazioni, così si trova in Launchpad e Spotlight (si chiude prima quella aperta)
pkill -x FotoTag 2>/dev/null && sleep 1
rm -rf /Applications/FotoTag.app && ditto $APP /Applications/FotoTag.app
echo "Pronta: /Applications/FotoTag.app"
[ "$1" = "--no-apri" ] || open /Applications/FotoTag.app
