# Skrypty przygotowania komputera firmowego

Zestaw skryptow PowerShell do automatycznego przygotowania nowego komputera w srodowisku firmowym oraz do resetowania maszyny testowej.

---

## Zawartosc repozytorium

```
/
├──script/
│  ├── Uruchom-Setup.bat               # Uruchamia Setup-Firmowy.ps1 jako Administrator
│  ├── Uruchom-Deinstalator.bat        # Uruchamia Deinstalator.ps1 jako Administrator
│  └── files/
│      ├── Setup-Firmowy.ps1           # Glowny skrypt instalacyjny
│      └── Deinstalator.ps1            # Skrypt do czyszczenia maszyny testowej
├── LICENSE
└── README.md
```

---

## Wymagania

- Windows 10 / Windows 11
- Konto z uprawnieniami **Administratora**
- Folder z instalatorami — lokalnie `C:\instalki\` lub udział sieciowy (patrz nizej)

---

## Przygotowanie folderu z instalatorami

Utworz folder `C:\instalki\` i wgraj do niego nastepujace pliki:

| Plik | Aplikacja | Link do pobrania |
|------|-----------|-------------------|
| `AnyDesk.exe` | AnyDesk | https://anydesk.com/en/downloads/windows |
| `ees_nt64.msi` | ESET Endpoint Security | https://www.eset.com/int/business/download/endpoint-security/ |
| `googlechromestandaloneenterprise64.msi` | Google Chrome Enterprise | https://enterprise.google.com/chrome/chrome-browser/ |
| `Intel-Driver-and-Support-Assistant-Installer.exe` | Intel Driver & Support Assistant | https://www.intel.com/content/www/us/en/support/detect.html |
| `OfficeSetup32bitPL.exe` | Microsoft Office 32-bit PL | https://www.microsoft.com/pl-pl/microsoft-365/get-started-with-office-2021 |
| `AdobeReader_PL.exe` | Adobe Acrobat Reader PL (offline installer) | https://get.adobe.com/reader/enterprise/ |
| `UrBackup_Client.exe` | UrBackup Client (x86/x64) (10/11 + Server editions) | https://www.urbackup.org/download.html#client_windows |

> Aktualna lista wszystkich wersji/instalatorow UrBackup (rowniez wariant bez ikony w zasobniku i osobny instalator MSI x64) znajduje sie na oficjalnej stronie pobierania: https://www.urbackup.org/download.html

Nazwy plikow musza byc dokladnie takie jak powyzej (skrypt szuka ich po nazwie).

---

## Uruchomienie

### Instalacja (nowy komputer firmowy)

1. Skopiuj wszystkie pliki skryptow do dowolnego folderu
2. Kliknij **prawym przyciskiem myszy** na `Uruchom-Setup.bat`
3. Wybierz **"Uruchom jako administrator"**

> Jezeli plik `.bat` zostanie uruchomiony bez uprawnien admina, automatycznie poprosi o ich nadanie przez UAC.

### Deinstalacja (reset maszyny testowej)

1. Kliknij **prawym przyciskiem myszy** na `Uruchom-Deinstalator.bat`
2. Wybierz **"Uruchom jako administrator"**

> Nie uruchamiaj plikow `.ps1` bezposrednio — pliki `.bat` automatycznie ustawiaja wymagane uprawnienia i ExecutionPolicy.

---

## Co robi Setup-Firmowy.ps1

### Krok 0 — Nazwa komputera
- Wyswietla okno dialogowe z aktualna nazwa komputera
- Pozwala wpisac nowa nazwe (max 15 znakow, tylko litery/cyfry/myslniki)
- Zmiana wchodzi w zycie po restarcie

### Krok 1 — Ustawienia zasilania
- Wylacza wygaszacz ekranu
- Aktywuje plan zasilania "Wysoka wydajnosc"
- Ustawia wygaszenie ekranu i usypianie na **nigdy** (AC i DC)
- Wylacza hibernacje

### Krok 2a — Usuniecie McAfee
- Automatycznie wykrywa i usuwa McAfee Antivirus oraz McAfee WebAdvisor
- Czyści pozostale foldery McAfee

### Krok 2b — Usuniecie starego Office (metoda SaRA)
- Wykrywa instalacje Microsoft Office (wersje 14/15/16, Microsoft 365, Click-to-Run)
- Jezeli Office zostanie znaleziony — otwiera oficjalne narzedzie Microsoft do deinstalacji: **https://aka.ms/SaRA-officeUninstallFromPC**
- Skrypt czeka na potwierdzenie (ENTER) przed kontynuowaniem

> Uzywamy oficjalnej metody SaRA zamiast recznej deinstalacji, poniewaz gwarantuje ona pelne usuniecie bez pozostalosci.

### Krok 3 — Instalacja aplikacji

| Aplikacja | Tryb | Plik |
|-----------|------|------|
| AnyDesk | Silent (bez okienek) | `AnyDesk.exe` |
| ESET Endpoint Security | Silent (bez okienek) | `ees_nt64.msi` |
| Google Chrome Enterprise | Silent (bez okienek) | `googlechromestandaloneenterprise64.msi` |
| Intel Driver & Support Assistant | Silent (bez okienek) | `Intel-Driver-and-Support-Assistant-Installer.exe` |
| Microsoft Office 32-bit PL | Reczna (otwiera instalator) | `OfficeSetup32bitPL.exe` |
| Adobe Acrobat Reader PL | Silent (bez okienek) | `AdobeReader_PL.exe` |
| UrBackup Client 2.5.32 | Silent (bez okienek), flaga `/S` | `UrBackup_Client.exe` |

> **Uwaga — Office 32-bit na systemie 64-bit:** Skrypt wykrywa architekture systemu. Jezeli system jest 64-bitowy, wyswietli ostrzezenie i zapyta o potwierdzenie przed uruchomieniem instalatora 32-bit. Jezeli instalacja sie nie powiedzie, pobierz wersje 64-bit Office.

> **Uwaga — UrBackup:** od tej wersji skryptu uzywany jest uniwersalny instalator EXE `UrBackup_Client.exe` (x86/x64, z ikona w zasobniku), instalowany cicho parametrem `/S`, zamiast poprzedniego pliku `UrBackup_Client.msi` (MSI x64-only).

### Krok 4 — Przywrocenie ExecutionPolicy
- Usuwa nadpisanie polityki na poziomie `Process` i `CurrentUser`
- Przywraca `ExecutionPolicy` do `Restricted` na poziomie `LocalMachine`
- Jezeli polityka jest zarzadzana przez GPO (domena) — blad jest ignorowany (normalne zachowanie)

---

## Co robi Deinstalator.ps1

Usuwa wszystkie aplikacje zainstalowane przez `Setup-Firmowy.ps1` i cofa ustawienia systemowe:

| Co usuwa | Metoda |
|----------|--------|
| AnyDesk | Przez wbudowany `--remove` lub rejestr |
| ESET Endpoint Security | MSI silent uninstall |
| Google Chrome | MSI silent uninstall + czyszczenie folderow |
| Intel Driver & Support Assistant | Rejestr silent uninstall |
| McAfee / McAfee WebAdvisor | Rejestr silent uninstall + czyszczenie folderow |
| Microsoft Office | Oficjalne narzedzie SaRA (strona Microsoft) |
| Adobe Acrobat Reader | Rejestr silent uninstall + czyszczenie folderow |
| UrBackup Client | Rejestr silent uninstall (uninstall.exe `/S`) + czyszczenie folderow |

Dodatkowo:
- Cofa ustawienia zasilania do domyslnych Windows (ekran: 10 min AC / 5 min DC, uśpienie: 30 min AC / 15 min DC, hibernacja wlaczona, wygaszacz 10 min)
- Przywraca ExecutionPolicy do `Restricted` (z tym samym zabezpieczeniem przed bledem GPO)

> **Uwaga — UrBackup:** wpis deinstalacyjny UrBackup Client 2.5.32 w rejestrze wskazuje na wlasny `uninstall.exe` (instalator NSIS), a nie na `msiexec`. Funkcja `Uninstall-ByName` w `Deinstalator.ps1` automatycznie to rozpoznaje i uruchamia deinstalator z flagami cichego trybu (`/S /silent /quiet /norestart`) — nie jest wymagana zadna dodatkowa zmiana konfiguracji.

---

## Dodawanie kolejnych aplikacji

W pliku `Setup-Firmowy.ps1` znajdz sekcje z komentarzem:

```
>> DODAJ KOLEJNE APLIKACJE TUTAJ <<
```

Przykladowe uzycie:

```powershell
# Silent .exe (np. 7-Zip)
Install-App -Name "7-Zip" -File "7z2301-x64.exe" -SilentArgs "/S" -Silent $true

# Silent .msi
$msi = Join-Path $InstallerPath "program.msi"
Start-Process "msiexec.exe" -ArgumentList "/qn /i `"$msi`" /norestart" -Wait

# Reczna instalacja
Install-App -Name "Program" -File "setup.exe" -Silent $false
```

---

## Aktywacja licencji ESET

W sekcji ESET w skrypcie znajdz linie:

```powershell
-ArgumentList "/qn /i `"$esetMsi`" ADDLOCAL=ALL REBOOT_WHEN_NEEDED=0"
```

I dodaj na koncu parametr z kluczem:

```powershell
-ArgumentList "/qn /i `"$esetMsi`" ADDLOCAL=ALL REBOOT_WHEN_NEEDED=0 ACTIVATION_DATA=key:AAAA-BBBB-CCCC-DDDD-EEEE"
```

---

## Najczestsze problemy

**Skrypt nie uruchamia sie**
Upewnij sie ze uruchamiasz przez `.bat`, a nie bezposrednio plik `.ps1`. Jezeli mimo to nie dziala, uruchom PowerShell jako Administrator i wpisz:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

**Nie znaleziono pliku instalatora**
Sprawdz czy nazwy plikow w folderze z instalatorami sa identyczne jak w tabeli powyzej (wielkosc liter ma znaczenie). W przypadku UrBackup plik musi nazywac sie dokladnie `UrBackup_Client.exe`.

**Brak dostepu do udzialu sieciowego**
Upewnij sie ze komputer jest podlaczony do sieci firmowej i ma uprawnienia do odczytu udzialu. Mozesz sprawdzic dostep w PowerShell: `Test-Path \\nazwaservera\instalki`

**ESET zwraca blad instalacji**
Upewnij sie ze poprzednia wersja ESET lub inny antywirus zostal calkowicie odinstalowany przed uruchomieniem skryptu.

**Adobe nie instaluje sie cicho**
Upewnij sie ze masz offline installer z **https://get.adobe.com/reader/enterprise/** — zwykly plik ze strony Adobe to web downloader i nie obsluguje silent install.

**Office 32-bit nie instaluje sie na systemie 64-bit**
Microsoft moze blokowac instalacje 32-bit na systemach 64-bit. W takim przypadku pobierz i uzyj instalatora 64-bit Office.

**Office nie instaluje sie po usunieciu starego**
Zrestartuj komputer po deinstalacji przez SaRA i uruchom skrypt ponownie.

**Blad ExecutionPolicy na koncu skryptu**
Jezeli widzisz komunikat o nadpisaniu przez GPO — to normalne w srodowisku domenowym. Skrypt ignoruje ten blad i kontynuuje.

**McAfee nie zostal usuniety do konca**
Niektore wersje McAfee wymagaja dedykowanego narzedzia MCPR (McAfee Consumer Product Removal). Pobierz je ze strony McAfee i uruchom recznie.

**UrBackup Client nie instaluje sie / nie odinstalowuje cicho**
Upewnij sie ze uzywasz instalatora EXE (nie MSI) o dokladnej nazwie `UrBackup_Client.exe`, pobranego z https://www.urbackup.org/download.html#client_windows. Starsze pliki `UrBackup_Client.msi` nie sa juz obslugiwane przez `Setup-Firmowy.ps1` — jesli musisz uzywac MSI (np. z powodu polityk GPO wymuszajacych pakiety MSI), pobierz `UrBackup Client 2.5.32(x64).msi` i przywroc blok `msiexec` w skrypcie.

---

## Licencja

Skrypty sa dostepne do dowolnego uzytku w srodowiskach firmowych.

---
---

# Corporate PC Provisioning Scripts

A collection of PowerShell scripts for automated setup of new corporate workstations and for resetting test machines to a clean state.

---

## Repository Structure

```
/
├──script/
│  ├── Uruchom-Setup.bat               # Launches Setup-Firmowy.ps1 as Administrator
│  ├── Uruchom-Deinstalator.bat        # Launches Deinstalator.ps1 as Administrator
│  └── files/
│      ├── Setup-Firmowy.ps1           # Main installation script
│      └── Deinstalator.ps1            # Script for cleaning up test machines
├── LICENSE
└── README.md
```

---

## Requirements

- Windows 10 / Windows 11
- **Administrator** account privileges
- Installation files folder — local `C:\instalki\` or a network share (see below)

---

## Preparing the Installation Folder

Create the folder `C:\instalki\` and place the following files inside:

| File Name | Application | Download link |
|-----------|-------------|----------------|
| `AnyDesk.exe` | AnyDesk | https://anydesk.com/en/downloads/windows |
| `ees_nt64.msi` | ESET Endpoint Security | https://www.eset.com/int/business/download/endpoint-security/ |
| `googlechromestandaloneenterprise64.msi` | Google Chrome Enterprise | https://enterprise.google.com/chrome/chrome-browser/ |
| `Intel-Driver-and-Support-Assistant-Installer.exe` | Intel Driver & Support Assistant | https://www.intel.com/content/www/us/en/support/detect.html |
| `OfficeSetup32bitPL.exe` | Microsoft Office 32-bit (Polish) | https://www.microsoft.com/pl-pl/microsoft-365/get-started-with-office-2021 |
| `AdobeReader_PL.exe` | Adobe Acrobat Reader PL (offline installer) | https://get.adobe.com/reader/enterprise/ |
| `UrBackup_Client.exe` | UrBackup Client (x86/x64) (10/11 + Server editions) | https://www.urbackup.org/download.html#client_windows |

> The full, always-current list of UrBackup client builds (including the no-tray-icon variant and the standalone x64 MSI installer) is available on the official download page: https://www.urbackup.org/download.html

> **Note:** File names must match the table exactly — the script identifies them by name.

---

## Usage

### Installation (New Corporate PC)

1. Copy all script files to any folder.
2. **Right-click** `Uruchom-Setup.bat`.
3. Select **"Run as administrator"**.

> If launched without admin rights, the `.bat` file will automatically prompt for elevation via UAC.

### Uninstallation (Test Machine Reset)

1. **Right-click** `Uruchom-Deinstalator.bat`.
2. Select **"Run as administrator"**.

> Do not run `.ps1` files directly — the `.bat` files handle the required permissions and `ExecutionPolicy` bypass automatically.

---

## What Setup-Firmowy.ps1 Does

### Step 0 — Computer Name
- Displays a dialog with the current computer name.
- Allows entry of a new name (max 15 characters, alphanumeric and hyphens only).
- The name change takes effect after a reboot.

### Step 1 — Power Settings
- Disables the screensaver.
- Activates the **"High Performance"** power plan.
- Sets screen timeout and sleep to **Never** (AC and DC).
- Disables Hibernation.

### Step 2a — McAfee Removal
- Detects and silently removes McAfee Antivirus and McAfee WebAdvisor.
- Cleans up residual McAfee folders.

### Step 2b — Legacy Office Removal (SaRA Method)
- Detects Microsoft Office installations (versions 14/15/16, Microsoft 365, Click-to-Run).
- If Office is found, opens Microsoft's official removal tool: **https://aka.ms/SaRA-officeUninstallFromPC**
- The script waits for confirmation (ENTER) before continuing.

> The official SaRA tool is used instead of manual uninstallation to ensure complete removal without leftovers.

### Step 3 — Application Installation

| Application | Mode | File |
|-------------|------|------|
| AnyDesk | Silent (background) | `AnyDesk.exe` |
| ESET Endpoint Security | Silent (background) | `ees_nt64.msi` |
| Google Chrome Enterprise | Silent (background) | `googlechromestandaloneenterprise64.msi` |
| Intel Driver & Support Assistant | Silent (background) | `Intel-Driver-and-Support-Assistant-Installer.exe` |
| Microsoft Office 32-bit PL | Manual (opens installer UI) | `OfficeSetup32bitPL.exe` |
| Adobe Acrobat Reader PL | Silent (background) | `AdobeReader_PL.exe` |
| UrBackup Client | Silent (background), `/S` flag | `UrBackup_Client.exe` |

> **Office 32-bit on a 64-bit OS:** The script detects system architecture. On a 64-bit OS it will display a warning and ask for confirmation before launching the 32-bit installer. If installation fails, use the 64-bit Office installer instead.

> **UrBackup:** as of this version, the script uses the universal EXE installer `UrBackup_Client.exe` (x86/x64, with tray icon), installed silently via the `/S` flag, replacing the previous `UrBackup_Client.msi` file (x64-only MSI).

### Step 4 — Security Cleanup
- Removes `ExecutionPolicy` overrides at the `Process` and `CurrentUser` scopes.
- Restores `ExecutionPolicy` to `Restricted` at the `LocalMachine` scope.
- If policy is managed by GPO (domain environment), the error is safely ignored.

---

## What Deinstalator.ps1 Does

Removes all applications installed by `Setup-Firmowy.ps1` and reverts system settings:

| What it removes | Method |
|-----------------|--------|
| AnyDesk | Built-in `--remove` flag or registry |
| ESET Endpoint Security | MSI silent uninstall |
| Google Chrome | MSI silent uninstall + folder cleanup |
| Intel Driver & Support Assistant | Registry silent uninstall |
| McAfee / McAfee WebAdvisor | Registry silent uninstall + folder cleanup |
| Microsoft Office | Official SaRA tool (Microsoft website) |
| Adobe Acrobat Reader | Registry silent uninstall + folder cleanup |
| UrBackup Client | Registry silent uninstall (`uninstall.exe /S`) + folder cleanup |

Additionally:
- Resets power settings to Windows defaults (screen: 10 min AC / 5 min DC, sleep: 30 min AC / 15 min DC, hibernation enabled, screensaver: 10 min).
- Restores `ExecutionPolicy` to `Restricted` (with the same GPO-safe error handling).

> **UrBackup:** the registry uninstall entry for UrBackup Client 2.5.32 points to its own NSIS `uninstall.exe` rather than `msiexec`. The `Uninstall-ByName` helper in `Deinstalator.ps1` detects this automatically and runs the uninstaller with silent flags (`/S /silent /quiet /norestart`) — no extra configuration is required.

---

## Adding New Applications

In `Setup-Firmowy.ps1`, find the section marked:

```
>> DODAJ KOLEJNE APLIKACJE TUTAJ <<
```

Examples:

```powershell
# Silent .exe (e.g. 7-Zip)
Install-App -Name "7-Zip" -File "7z2301-x64.exe" -SilentArgs "/S" -Silent $true

# Silent .msi
$msi = Join-Path $InstallerPath "program.msi"
Start-Process "msiexec.exe" -ArgumentList "/qn /i `"$msi`" /norestart" -Wait

# Manual installation
Install-App -Name "Custom Program" -File "setup.exe" -Silent $false
```

---

## ESET License Activation

Find the ESET section in the script and update the arguments:

**Find:**
```powershell
-ArgumentList "/qn /i `"$esetMsi`" ADDLOCAL=ALL REBOOT_WHEN_NEEDED=0"
```

**Replace with:**
```powershell
-ArgumentList "/qn /i `"$esetMsi`" ADDLOCAL=ALL REBOOT_WHEN_NEEDED=0 ACTIVATION_DATA=key:AAAA-BBBB-CCCC-DDDD-EEEE"
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Script won't run | Use the `.bat` file, not `.ps1` directly. If it still fails, run PowerShell as Admin and execute: `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine` |
| Installer not found | Verify file names in the installers folder match the table exactly (case-sensitive). For UrBackup the file must be named exactly `UrBackup_Client.exe`. |
| No access to network share | Ensure the machine is connected to the corporate network and has read access to the share. You can test it in PowerShell: `Test-Path \\servername\instalki` |
| ESET installation error | Ensure all previous antivirus software is fully removed before running the script. |
| Adobe won't install silently | Make sure you have the offline installer from **https://get.adobe.com/reader/enterprise/** — the standard Adobe download is a web installer and does not support silent install. |
| Office 32-bit blocked on 64-bit OS | Microsoft may block 32-bit installs on 64-bit systems. Download and use the 64-bit Office installer. |
| Office won't install after removal | Reboot after the SaRA uninstall completes, then run the script again. |
| ExecutionPolicy error at the end | If you see a GPO override message, this is normal in domain environments — the script handles it safely. |
| McAfee not fully removed | Some McAfee versions require the dedicated MCPR tool. Download it from the McAfee website and run it manually. |
| UrBackup Client won't install/uninstall silently | Confirm you're using the EXE installer (not MSI), named exactly `UrBackup_Client.exe`, downloaded from https://www.urbackup.org/download.html#client_windows. The old `UrBackup_Client.msi` file is no longer used by `Setup-Firmowy.ps1` — if you must use MSI (e.g. due to GPO policies requiring MSI packages), download `UrBackup Client 2.5.32(x64).msi` and restore the `msiexec` block in the script. |

---

## License

These scripts are provided for free use within corporate environments. Use responsibly.