#!/bin/sh
# Builds Neko.app without Xcode (Command Line Tools are enough).
#   ./build.sh            -> build/Neko.app
#   ./build.sh install    -> also copies it to ~/Applications/Neko.app
set -e

APP=build/Neko.app
SDK=$(xcrun --show-sdk-path)
SCRATCH=$(mktemp -d /tmp/neko-build.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# A quarantine flag on the source tree (it is inherited by everything a browser
# downloads) makes Gatekeeper report the built app as damaged and kill it.
if xattr "$PWD" 2>/dev/null | grep -q com.apple.quarantine; then
	echo "warning: $PWD is quarantined, the app will not launch from here."
	echo "         fix with: xattr -dr com.apple.quarantine \"$PWD\""
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

sed -e 's/${PRODUCT_NAME}/Neko/g' -e 's/${EXECUTABLE_NAME}/Neko/g' \
	Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --noqtn/--noextattr: never carry a download quarantine into the bundle.
ditto --noextattr --noqtn Resources "$APP/Contents/Resources"

# The plugins that ship with the app. They are copied into the container on first
# launch and switched on there; inside the bundle they are read-only and signed
# with everything else.
if [ -d Plugins ]; then
	ditto --noextattr --noqtn Plugins "$APP/Contents/Resources/Plugins"
fi

# The examples. Not in Plugins/, because that folder is seeded into the container
# and switched on: these two want three Shortcuts each that nobody has yet, and
# enabling both at once means two cats answering the same sentence. They ship so
# that somebody who has just read about verbs has something to point Add… at.
if [ -d examples ]; then
	ditto --noextattr --noqtn examples "$APP/Contents/Resources/Examples"
fi

# arm64 only. This project is Apple silicon and says so everywhere: the local
# model engine is a Metal build, Apple Intelligence needs Apple silicon, and the
# Command Line Tools ship the Swift compatibility libraries for arm64 alone — so
# the Intel half of the universal binary that used to come out of here was an app
# without a local model, without Apple's model, and without the Swift file that
# reaches it. A slice that cannot do the things the app is for is worse than no
# slice at all.
#
# Swift is here for one file: FoundationModels ships no headers, so Apple's
# on-device model can only be reached from Swift.
SOURCES="src/main.m src/MyView.m src/MyPanel.m src/NekoCharacter.m src/NekoController.m
	src/NekoAnswerProvider.m src/NekoShortcutProvider.m src/NekoModelProvider.m
	src/NekoAppleProvider.m src/NekoOpenAIProvider.m src/NekoKeychain.m
	src/NekoModelStore.m src/NekoLocalProvider.m
	src/NekoHotKey.m src/NekoListener.m src/NekoBubble.m src/NekoLine.m src/NekoAsk.m
	src/NekoAdvisor.m src/NekoAntics.m src/NekoDesktop.m src/NekoPainter.m src/NekoSense.m src/NekoAction.m src/NekoFolderAccess.m src/NekoWakeWord.m src/NekoPermissions.m src/NekoBrains.m src/NekoMemory.m src/NekoRate.m src/NekoWeb.m src/NekoVoice.m src/NekoPlace.m src/NekoPlayer.m src/NekoPlugin.m src/NekoPlugins.m src/NekoPluginText.m src/NekoPluginVerbs.m src/NekoPluginsPanel.m src/NekoNoise.m src/NekoRecall.m
src/NekoRecord.m
src/NekoUnseen.m
src/NekoUpdate.m
src/NekoSelf.m
src/NekoWords.m src/NekoWhen.m
src/NekoClock.m
src/NekoSums.m src/NekoTimer.m src/NekoPhrase.m src/NekoPluginRoutes.m src/NekoStream.m src/NekoFact.m src/NekoDoors.m src/NekoAppointment.m src/NekoGlance.m src/NekoPermissionsTab.m"
FRAMEWORKS="-framework Cocoa -framework ServiceManagement -framework Carbon
	-framework Security -framework AVFoundation -framework NaturalLanguage -framework IOKit -framework CoreLocation -framework CoreAudio
	-Xlinker -weak_framework -Xlinker Speech"
DEPLOYMENT=11.0

# A local model needs an engine, and the engine is llama.cpp. It is built once
# into a cache rather than vendored: 200 MB of C++ has no business in this
# repository, and pinning the tag keeps the result reproducible. Only the
# machine doing the building needs the network and cmake — the app that comes
# out is self-contained.
SD_COMMIT=97d2990807fe6d558e395f8764198d7c7e7b411c
SD_CACHE="$HOME/Library/Caches/neko-sd"

LLAMA_TAG=b10581
LLAMA_CACHE="$HOME/Library/Caches/neko-llama/$LLAMA_TAG"
# Found rather than listed: the layout under build/ has moved between releases.
llama_libs() {
	find "$LLAMA_CACHE/build" -name "libllama.a" -o -name "libggml*.a" | tr '\n' ' '
}

ensure_llama() {
	[ -f "$LLAMA_CACHE/build/src/libllama.a" ] && return 0
	if ! command -v cmake >/dev/null 2>&1; then
		echo "note: cmake is missing, so the app is built without a local model engine"
		return 1
	fi
	echo "building llama.cpp $LLAMA_TAG once, into $LLAMA_CACHE (a few minutes)"
	mkdir -p "$LLAMA_CACHE"
	if [ ! -d "$LLAMA_CACHE/src" ]; then
		git clone --depth 1 --branch "$LLAMA_TAG" \
			https://github.com/ggml-org/llama.cpp "$LLAMA_CACHE/src" >/dev/null 2>&1 || return 1
	fi
	cmake -S "$LLAMA_CACHE/src" -B "$LLAMA_CACHE/build" \
		-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
		-DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_TOOLS=OFF \
		-DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF \
		-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT >/dev/null 2>&1 || return 1
	cmake --build "$LLAMA_CACHE/build" --target llama -j 8 >/dev/null 2>&1 || return 1
	return 0
}

if ensure_llama; then
	HAVE_LLAMA=yes
else
	HAVE_LLAMA=no
fi

# The drawing half is a separate program rather than a library, because
# stable-diffusion.cpp carries its own ggml and the app already has llama.cpp's:
# linked together, every ggml symbol would be defined twice. A helper also means
# a model that crashes or eats a gigabyte takes nothing of the cat with it.
ensure_diffusion() {
	[ -x "$SD_CACHE/build/bin/sd-cli" ] && return 0
	command -v cmake >/dev/null 2>&1 || return 1
	echo "building stable-diffusion.cpp once, into $SD_CACHE (several minutes)"
	mkdir -p "$SD_CACHE"
	if [ ! -d "$SD_CACHE/src/.git" ]; then
		mkdir -p "$SD_CACHE/src"
		( cd "$SD_CACHE/src" \
		  && git init -q . \
		  && git remote add origin https://github.com/leejet/stable-diffusion.cpp \
		  && git fetch -q --depth 1 origin "$SD_COMMIT" \
		  && git checkout -q FETCH_HEAD \
		  && git submodule update -q --init --depth 1 --recursive ) >/dev/null 2>&1 || return 1
	fi
	cmake -S "$SD_CACHE/src" -B "$SD_CACHE/build" \
		-DCMAKE_BUILD_TYPE=Release -DSD_METAL=ON \
		-DGGML_METAL_EMBED_LIBRARY=ON -DSD_BUILD_SHARED_LIBS=OFF \
		-DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null 2>&1 || return 1
	# Only the command line target: the server example wants pnpm and Node to
	# build a web front end nobody here is going to look at.
	cmake --build "$SD_CACHE/build" --config Release -j 8 --target sd-cli >/dev/null 2>&1 || return 1
	return 0
}

if ensure_diffusion; then
	HAVE_DIFFUSION=yes
else
	HAVE_DIFFUSION=no
	echo "note: the app is built without the drawing helper"
fi
ARCH=arm64
SLICE=$SCRATCH/$ARCH
mkdir -p "$SLICE"

# -parse-as-library: without it a lone Swift file is treated as a script and
# brings its own main().
swiftc -module-name "Neko" -target "$ARCH-apple-macos$DEPLOYMENT" -sdk "$SDK" -O -parse-as-library \
	-c src/NekoAppleModel.swift -o "$SLICE/NekoAppleModel.o" -emit-objc-header-path "src/Neko-Swift.h"

for SOURCE in $SOURCES; do
	clang -arch "$ARCH" -fno-objc-arc -fblocks -O2 -isysroot "$SDK" \
		-mmacosx-version-min=$DEPLOYMENT -Wno-deprecated-declarations \
		-c "$SOURCE" -o "$SLICE/$(basename "$SOURCE" .m).o"
done

if [ "$HAVE_LLAMA" = yes ]; then
	# Objective-C++: llama.cpp is C with C++ headers.
	clang++ -arch "$ARCH" -fno-objc-arc -x objective-c++ -std=c++17 -O2 \
		-isysroot "$SDK" -mmacosx-version-min=$DEPLOYMENT \
		-Isrc -I"$LLAMA_CACHE/src/include" -I"$LLAMA_CACHE/src/ggml/include" \
		-c src/NekoLlamaEngine.mm -o "$SLICE/NekoLlamaEngine.o"
	LLAMA_LINK="$(llama_libs) -lc++ -framework Metal -framework MetalKit -framework Accelerate"
else
	LLAMA_LINK=""
fi

# Linked by swiftc, which knows where the Swift runtime lives.
swiftc -target "$ARCH-apple-macos$DEPLOYMENT" -sdk "$SDK" \
	"$SLICE"/*.o $LLAMA_LINK $FRAMEWORKS -framework FoundationModels \
	-o "$APP/Contents/MacOS/Neko" -module-name "Neko"

# The drawing helper travels inside the bundle, signed with everything else.
if [ "$HAVE_DIFFUSION" = yes ]; then
	cp "$SD_CACHE/build/bin/sd-cli" "$APP/Contents/MacOS/neko-paint"
	chmod +x "$APP/Contents/MacOS/neko-paint"
else
	rm -f "$APP/Contents/MacOS/neko-paint"
fi

xattr -cr "$APP"
codesign --sign - --entitlements Neko.entitlements --force "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

if [ "$1" = install ]; then
	DEST=$HOME/Applications/Neko.app
	mkdir -p "$HOME/Applications"
	rm -rf "$DEST"
	ditto --noextattr --noqtn "$APP" "$DEST"
	xattr -cr "$DEST"
	codesign --sign - --entitlements Neko.entitlements --force "$DEST"
	echo "installed $DEST"
fi
