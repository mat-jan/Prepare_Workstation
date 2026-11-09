# Prepare Workstation — kreator przygotowania komputera firmowego

Program z oknem graficznym (PowerShell + WinForms) do przygotowania nowego komputera w środowisku firmowym: nazwa, zasilanie, usunięcie McAfee i starego Office, instalacja aplikacji, kilka ustawień systemu, log i podsumowanie.

> English version: [README.en.md](README.en.md)

---

## Zawartość repozytorium

```
/
├── script/
│   ├── Start-Firmowy.bat        # uruchamia kreator jako Administrator
│   └── files/
│       ├── Setup-Firmowy.ps1    # kreator (GUI)
│       └── apps.json            # lista aplikacji do instalacji
├── build/
│   └── Build-Package.ps1        # buduje paczki ZIP/EXE
├── .github/workflows/           # CI i automatyczne wydania
├── LICENSE
└── README.md
```

Folder `files\` musi leżeć obok `Start-Firmowy.bat` (nie przenoś plików osobno).

---

## Wymagania

- Windows 10 / 11 (Windows PowerShell 5.1 — jest w systemie)
- Konto z uprawnieniami **Administratora**
- Folder z instalatorami — domyślnie `C:\instalki\`, można wskazać inny (też udział sieciowy) w oknie programu lub parametrem `-InstallerPath`

---

## Uruchomienie

1. Skopiuj repozytorium na komputer (lub na pendrive).
2. Uruchom **`script\Start-Firmowy.bat`** (bez uprawnień admina poprosi o nie przez UAC).
3. Ustaw opcje w zakładkach, kliknij **Uruchom**.

> Nie uruchamiaj `.ps1` bezpośrednio — `.bat` ustawia uprawnienia, tryb STA (wymagany przez GUI) i omija ExecutionPolicy tylko dla tego procesu.

---

## Okno programu

### Zakładka „Ustawienia”

| Sekcja | Co robi |
|--------|---------|
| Folder z instalatorami | Ścieżka do folderu z plikami (przycisk Przeglądaj); lista aplikacji odświeża się po zmianie |
| Nazwa komputera | Walidacja na żywo (litery, cyfry, myślniki, max 15 znaków, nie same cyfry); zmiana po restarcie |
| Zasilanie | Plan Wysoka wydajność (jeśli go nie ma na sprzęcie — tworzony z szablonu), ekran/uśpienie = nigdy, hibernacja off, wygaszacz off |
| Czyszczenie przed instalacją | Usunięcie McAfee (Antivirus, WebAdvisor + foldery) oraz starego Office oficjalnym narzędziem SaRA |
| Dodatkowe ustawienia | Punkt przywracania systemu, strefa czasowa + synchronizacja czasu, widoczne rozszerzenia plików i ukryte pliki, ikona „Ten komputer” na pulpicie |
| Opcje instalacji | Pomijanie już zainstalowanych aplikacji, opcjonalny klucz aktywacyjny ESET |
| Na koniec | Przywrócenie ExecutionPolicy (Restricted), otwarcie Windows Update |

### Zakładka „Aplikacje”

Lista z `apps.json`. Dla każdej pozycji widać: czy plik instalatora jest w folderze, czy aplikacja jest już zainstalowana i w jakim trybie się instaluje. Pozycje bez pliku są wyszarzone i odznaczone. Przyciski: zaznacz/odznacz wszystkie, odśwież, **Edytuj apps.json**.

**Instalatory z pendrive'a — bez kopiowania do `C:\instalki`:**

- **Przeciągnij** pliki instalatorów albo cały folder z pendrive'a na okno programu.
- **Dodaj pliki...** — zwykłe okno wyboru plików (zawsze działa).
- **Znajdź na pendrive** — przeszukuje dyski wymienne (do 3 poziomów folderów).

Program dopasowuje pliki po nazwie z `apps.json` (wielkość liter nie ma znaczenia), zaznacza je i używa **bezpośrednio z pendrive'a** — nie wyjmuj go do końca instalacji. Pliki, które nie pasują do żadnej aplikacji, są ignorowane. Kolumna „Plik w folderze” pokazuje wtedy „dodany ręcznie”.

> Windows domyślnie blokuje przeciąganie z zwykłego Eksploratora do okna uruchomionego jako Administrator. Program próbuje to obejść, ale jeśli przeciąganie nie działa (ikona zakazu), użyj **Dodaj pliki...** albo **Znajdź na pendrive**.

### Zakładka „Przebieg”

Kolorowy log na żywo. Ten sam log trafia do pliku w `C:\ProgramData\PrepareWorkstation\logs\` (przycisk **Folder logów**).

### Pasek na dole

- **Uruchom** — pokazuje listę kroków do potwierdzenia, potem wykonuje je po kolei z paskiem postępu.
- **Przerwij** — kończy bieżący krok i zatrzymuje resztę (instalatora w połowie nie ubija).
- **Tryb testowy** — symulacja: pokazuje co by się stało, niczego nie zmienia ani nie instaluje.
- Na końcu: podsumowanie (OK / pominięte / błędy) i pytanie o restart, jeśli jest potrzebny.

---

## Przygotowanie folderu z instalatorami

Domyślne nazwy plików (zmienisz je w `apps.json`):

| Plik | Aplikacja | Tryb | Link do pobrania |
|------|-----------|------|------------------|
| `AnyDesk.exe` | AnyDesk | cichy | https://anydesk.com/en/downloads/windows |
| `ees_nt64.msi` | ESET Endpoint Security | cichy (MSI) | https://www.eset.com/int/business/download/endpoint-security/ |
| `googlechromestandaloneenterprise64.msi` | Google Chrome Enterprise | cichy (MSI) | https://enterprise.google.com/chrome/chrome-browser/ |
| `Intel-Driver-and-Support-Assistant-Installer.exe` | Intel Driver & Support Assistant | cichy | https://www.intel.com/content/www/us/en/support/detect.html |
| `OfficeSetup32bitPL.exe` | Microsoft Office 32-bit PL | ręczny | https://www.microsoft.com/pl-pl/microsoft-365/get-started-with-office-2021 |
| `AdobeReader_PL.exe` | Adobe Acrobat Reader PL (offline) | cichy | https://get.adobe.com/reader/enterprise/ |
| `UrBackup_Client.exe` | UrBackup Client (x86/x64) | cichy, `/S` | https://www.urbackup.org/download.html#client_windows |

> Office 32-bit na systemie 64-bit: program pyta o potwierdzenie przed uruchomieniem instalatora.

---

## Dodawanie aplikacji — `apps.json`

Nie trzeba już edytować skryptu. Dopisz obiekt do `script\files\apps.json` (albo kliknij **Edytuj apps.json** w oknie) i **Odśwież listę**:

```json
{
  "id": "vlc",
  "name": "VLC media player",
  "file": "vlc-3.0.21-win64.exe",
  "type": "exe",
  "args": "/L=1045 /S",
  "detect": "^VLC media player",
  "default": false
}
```

| Pole | Znaczenie |
|------|-----------|
| `id` | unikalny identyfikator (`eset` ma specjalną obsługę klucza aktywacyjnego) |
| `name` | nazwa wyświetlana |
| `file` | nazwa pliku w folderze z instalatorami |
| `type` | `exe` (cichy), `msi` (uruchamiany przez `msiexec /qn /i`), `manual` (otwiera instalator i czeka) |
| `args` | argumenty instalatora (dla `msi` dopisywane po `/qn /i "plik" /norestart`) |
| `detect` | wyrażenie regularne dopasowywane do nazwy w „Programy i funkcje” — służy do pomijania już zainstalowanych |
| `default` | czy zaznaczać domyślnie |
| `warn32on64` | (opcjonalnie) ostrzeżenie dla instalatora 32-bit na systemie 64-bit |

---

## Aktywacja licencji ESET

Wpisz klucz w polu **Klucz ESET** (Ustawienia → Opcje instalacji). Zostanie przekazany instalatorowi jako `ACTIVATION_DATA=key:...`. Klucz nie jest zapisywany w logu ani w żadnym pliku.

---

## Wydania i paczki

Gotowe paczki są w zakładce **Releases** na GitHubie:

| Plik | Zawartość |
|------|-----------|
| `PrepareWorkstation-<wersja>.zip` | `Start-Firmowy.bat` + `files\` (skrypt i `apps.json`) + szablon folderu `instalki-template` + README |
| `PrepareWorkstation-exe-<wersja>.zip` | `Prepare-Workstation.exe` (samodzielny, wymaga admina) + `apps.json` obok pliku `.exe` + szablon + README |
| `SHA256SUMS.txt` | sumy kontrolne — sprawdź: `Get-FileHash plik.zip` |

> Plik `.exe` nie jest podpisany certyfikatem, więc SmartScreen lub antywirus mogą go oznaczyć. Wersja skryptowa (`.bat` + `.ps1`) jest przejrzysta i nie ma tego problemu.

Budowanie lokalnie (folder `dist\`):

```powershell
pwsh -File build\Build-Package.ps1 -Version 1.0.0            # tylko ZIP
powershell -File build\Build-Package.ps1 -Version 1.0.0 -WithExe   # ZIP + EXE (Windows)
```

Nowe wydanie tworzy się samo po wypchnięciu tagu: `git tag v1.0.0 && git push origin v1.0.0` (workflow `.github/workflows/release.yml`). Workflow `ci.yml` sprawdza składnię skryptów i `apps.json` przy każdym pushu.

---

## Najczęstsze problemy

| Problem | Rozwiązanie |
|---------|-------------|
| Okno się nie pojawia | Uruchom przez `Start-Firmowy.bat`. Okno PowerShella jest ukryte, błędy krytyczne pokazują się w okienku. Szczegóły w logu: `C:\ProgramData\PrepareWorkstation\logs\` |
| Aplikacja ma „BRAK” w kolumnie „Plik w folderze” | Nazwa pliku w folderze musi być taka jak w `apps.json` (wielkość liter nie ma znaczenia) |
| Brak dostępu do udziału sieciowego | Sprawdź w PowerShell: `Test-Path \\serwer\instalki`. Uwaga: po podniesieniu uprawnień (UAC) zmapowane dyski sieciowe mogą być niewidoczne — wpisz ścieżkę UNC |
| ESET zwraca błąd | Upewnij się, że poprzedni antywirus został w pełni usunięty (w razie potrzeby uruchom ponownie komputer) |
| Adobe nie instaluje się cicho | Potrzebny jest instalator **offline** z https://get.adobe.com/reader/enterprise/ |
| Office 32-bit zablokowany na 64-bit | Użyj instalatora 64-bit i zmień `file` w `apps.json` |
| Office nie instaluje się po usunięciu starego | Zrestartuj komputer po SaRA i uruchom ponownie |
| McAfee nie usunięty do końca | Niektóre wersje wymagają narzędzia MCPR od McAfee |
| Punkt przywracania nie powstał | Włącz Ochronę systemu dla dysku C:. Windows domyślnie pozwala na jeden punkt na 24 godziny |
| Zmiana wygaszacza/ikon dotyczy złego użytkownika | Ustawienia „HKCU” dotyczą konta, na które podniesiono uprawnienia. Jeśli UAC prosi o dane innego admina, zadziałają w jego profilu |

---

## Uwaga: usunięty deinstalator

Wcześniejsze wersje zawierały `Deinstalator.ps1` do czyszczenia maszyny testowej. Został usunięty z repozytorium (jest w historii gita). Czyszczenie McAfee i starego Office przed instalacją zostało w kreatorze.

---

## Licencja

Apache License 2.0 — patrz plik [LICENSE](LICENSE).
