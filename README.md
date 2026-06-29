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

### Opcja A — lokalny folder (pendrive / kopiowanie reczne)

Utworz folder `C:\instalki\` i wgraj do niego nastepujace pliki:

| Plik | Aplikacja |
|------|-----------|
| `AnyDesk.exe` | AnyDesk |
| `ees_nt64.msi` | ESET Endpoint Security |
| `googlechromestandaloneenterprise64.msi` | Google Chrome Enterprise |
| `Intel-Driver-and-Support-Assistant-Installer.exe` | Intel Driver & Support Assistant |
| `OfficeSetup32bitPL.exe` | Microsoft Office 32-bit PL |
| `AdobeReader_PL.exe` | Adobe Acrobat Reader PL (offline installer) |
| `UrBackup_Client.msi` | UrBackup Client |

Nazwy plikow musza byc dokladnie takie jak powyzej (skrypt szuka ich po nazwie).

### Opcja B — udział sieciowy (zalecane, bez pendrive)

Wrzuc instalatory na serwer/NAS i zmien jedna linijke na poczatku `Setup-Firmowy.ps1`:

```powershell
$InstallerPath = "\\nazwaservera\instalki"
```

Komputer musi byc podlaczony do sieci firmowej i miec dostep do udzialu. Nie trzeba nic kopiowac lokalnie — skrypt zaciagnie pliki bezposrednio po sieci.

### Pobieranie Adobe Acrobat Reader (offline installer)

Zwykly instalator ze strony Adobe to web downloader — nie dziala silent install. Pobierz pelny offline installer:

1. Wejdz na: **https://get.adobe.com/reader/enterprise/**
2. Wybierz: Windows / Polish / najnowsza wersja
3. Kliknij "Download Now"
4. Zapisz plik jako `AdobeReader_PL.exe` do folderu z instalatorami

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
| UrBackup Client | Silent (bez okienek) | `UrBackup_Client.msi` |

> **Uwaga — Office 32-bit na systemie 64-bit:** Skrypt wykrywa architekture systemu. Jezeli system jest 64-bitowy, wyswietli ostrzezenie i zapyta o potwierdzenie przed uruchomieniem instalatora 32-bit. Jezeli instalacja sie nie powiedzie, pobierz wersje 64-bit Office.

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
| UrBackup Client | Rejestr silent uninstall + czyszczenie folderow |

Dodatkowo:
- Cofa ustawienia zasilania do domyslnych Windows (ekran: 10 min AC / 5 min DC, uśpienie: 30 min AC / 15 min DC, hibernacja wlaczona, wygaszacz 10 min)
- Przywraca ExecutionPolicy do `Restricted` (z tym samym zabezpieczeniem przed bledem GPO)

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
Sprawdz czy nazwy plikow w folderze z instalatorami sa identyczne jak w tabeli powyzej (wielkosc liter ma znaczenie).

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

### Option A — Local folder (USB drive / manual copy)

Create the folder `C:\instalki\` and place the following files inside:

| File Name | Application |
|-----------|-------------|
| `AnyDesk.exe` | AnyDesk |
| `ees_nt64.msi` | ESET Endpoint Security |
| `googlechromestandaloneenterprise64.msi` | Google Chrome Enterprise |
| `Intel-Driver-and-Support-Assistant-Installer.exe` | Intel Driver & Support Assistant |
| `OfficeSetup32bitPL.exe` | Microsoft Office 32-bit (Polish) |
| `AdobeReader_PL.exe` | Adobe Acrobat Reader PL (offline installer) |
| `UrBackup_Client.msi` | UrBackup Client |

> **Note:** File names must match the table exactly — the script identifies them by name.

### Option B — Network share (recommended, no USB required)

Place the installers on a server or NAS and change one line at the top of `Setup-Firmowy.ps1`:

```powershell
$InstallerPath = "\\servername\instalki"
```

The machine must be connected to the corporate network and have read access to the share. No local copying needed — the script pulls files directly over the network.

### Downloading Adobe Acrobat Reader (offline installer)

The standard Adobe download is a web installer and does not support silent installation. Download the full offline installer instead:

1. Go to: **https://get.adobe.com/reader/enterprise/**
2. Select: Windows / Polish / latest version
3. Click "Download Now"
4. Save the file as `AdobeReader_PL.exe` to your installers folder

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
| UrBackup Client | Silent (background) | `UrBackup_Client.msi` |

> **Office 32-bit on a 64-bit OS:** The script detects system architecture. On a 64-bit OS it will display a warning and ask for confirmation before launching the 32-bit installer. If installation fails, use the 64-bit Office installer instead.

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
| UrBackup Client | Registry silent uninstall + folder cleanup |

Additionally:
- Resets power settings to Windows defaults (screen: 10 min AC / 5 min DC, sleep: 30 min AC / 15 min DC, hibernation enabled, screensaver: 10 min).
- Restores `ExecutionPolicy` to `Restricted` (with the same GPO-safe error handling).

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
| Installer not found | Verify file names in the installers folder match the table exactly (case-sensitive). |
| No access to network share | Ensure the machine is connected to the corporate network and has read access to the share. You can test it in PowerShell: `Test-Path \\servername\instalki` |
| ESET installation error | Ensure all previous antivirus software is fully removed before running the script. |
| Adobe won't install silently | Make sure you have the offline installer from **https://get.adobe.com/reader/enterprise/** — the standard Adobe download is a web installer and does not support silent install. |
| Office 32-bit blocked on 64-bit OS | Microsoft may block 32-bit installs on 64-bit systems. Download and use the 64-bit Office installer. |
| Office won't install after removal | Reboot after the SaRA uninstall completes, then run the script again. |
| ExecutionPolicy error at the end | If you see a GPO override message, this is normal in domain environments — the script handles it safely. |
| McAfee not fully removed | Some McAfee versions require the dedicated MCPR tool. Download it from the McAfee website and run it manually. |

---

## License

These scripts are provided for free use within corporate environments. Use responsibly.