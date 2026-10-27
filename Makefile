# Pelikan — skróty do budowania. Wymaga: Xcode 27, XcodeGen (brew install xcodegen), Docker/Colima dla bazy testowej.
SCHEME = Pelikan
DERIVED = build/DerivedData.noindex
APP = $(DERIVED)/Build/Products/Debug/Pelikan.app
PKG = Packages/PelikanKit

.PHONY: installer draft-release beta-release generate build release run test test-unit test-ssh test-integration test-release testdb report version clean strings

generate:
	xcodegen generate --quiet

build:
	./scripts/set-version.sh
	xcodebuild -project Pelikan.xcodeproj -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath $(DERIVED) -skipPackagePluginValidation -skipMacroValidation build -quiet

release:
	./scripts/set-version.sh
	xcodebuild -project Pelikan.xcodeproj -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -configuration Release -derivedDataPath $(DERIVED) -skipPackagePluginValidation -skipMacroValidation build -quiet

run: build
	open $(APP)

# Wszystkie testy pakietu: jednostkowe, SSH i integracyjne (te ostatnie wymagają bazy: make testdb).
test: test-unit test-ssh test-integration

# Bez bazy i bez SSH — tak jak krok „Testy jednostkowe” w CI.
test-unit:
	cd $(PKG) && swift test --skip 'PelikanDBTests|PelikanRemoteTests|PelikanProCTests'

# Testy SSH na lokalnym sshd (PelikanRemote, Pro*C): każdy zestaw osobno, z limitem czasu — jak w CI.
test-ssh:
	cd $(PKG) && swift build --build-tests
	scripts/ci-ssh-tests.sh

test-integration:
	cd $(PKG) && swift test --no-parallel --filter PelikanDBTests

# Testy wydajności w konfiguracji Release.
test-release:
	cd $(PKG) && PELIKAN_PERF_STRICT=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceTests

# Lokalna baza testowa (Oracle Free 26ai w kontenerze) ze schematami i utPLSQL.
testdb:
	./scripts/testdb.sh up && ./scripts/testdb.sh seed

# Raport postępów: docs/progress/index.html i ~/Pelikan-raport/index.html
report:
	python3 scripts/progress.py --heartbeat

version:
	@./scripts/version.sh

# Teksty interfejsu z kodu do String Catalog (potem tłumaczenia: scripts/l10n.py check --strict).
strings:
	python3 scripts/l10n.py extract

clean:
	rm -rf build $(PKG)/.build

# Instalatory DMG i PKG (podpis stałym certyfikatem — scripts/signing.sh) i szkic wydania na GitHubie (docs/WYDANIA.md).
installer:
	scripts/build-installer.sh

draft-release:
	scripts/release.sh


beta-release:
	scripts/release.sh --beta