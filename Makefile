# Pelikan — skróty do budowania. Wymaga: Xcode 27, XcodeGen (brew install xcodegen), Docker/Colima dla bazy testowej.
SCHEME = Pelikan
DERIVED = build/DerivedData.noindex
APP = $(DERIVED)/Build/Products/Debug/Pelikan.app
PKG = Packages/PelikanKit

.PHONY: installer draft-release generate build release run test test-unit test-integration test-release test-ui testdb report version clean strings

generate:
	xcodegen generate --quiet

build:
	./scripts/set-version.sh
	xcodebuild -project Pelikan.xcodeproj -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) -skipPackagePluginValidation -skipMacroValidation build -quiet

release:
	./scripts/set-version.sh
	xcodebuild -project Pelikan.xcodeproj -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED) -skipPackagePluginValidation -skipMacroValidation build -quiet

run: build
	open $(APP)

# Wszystkie testy pakietu: jednostkowe + integracyjne (te drugie wymagają bazy: make testdb).
test:
	cd $(PKG) && swift test --skip PelikanDBTests && swift test --no-parallel --filter PelikanDBTests

test-unit:
	cd $(PKG) && swift test --skip PelikanDBTests

test-integration:
	cd $(PKG) && swift test --no-parallel --filter PelikanDBTests

# Testy wydajności w konfiguracji Release.
test-release:
	cd $(PKG) && PELIKAN_PERF_STRICT=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceTests

test-ui:
	xcodebuild -project Pelikan.xcodeproj -scheme PelikanUITests -derivedDataPath $(DERIVED) test -quiet

# Lokalna baza testowa (Oracle Free 26ai w kontenerze) ze schematami i utPLSQL.
testdb:
	./scripts/testdb.sh up && ./scripts/testdb.sh seed

# Raport postępów: docs/progress/index.html i ~/Pelikan-raport/index.html
report:
	python3 scripts/progress.py --heartbeat

version:
	@./scripts/version.sh

strings:
	python3 scripts/gen-strings.py

clean:
	rm -rf build $(PKG)/.build

# Instalatory DMG i PKG (podpis stałym certyfikatem — scripts/signing.sh) i szkic wydania na GitHubie (docs/WYDANIA.md).
installer:
	scripts/build-installer.sh

draft-release:
	scripts/release.sh
