# Prepare Workstation — corporate PC setup wizard

A GUI tool (PowerShell + WinForms) for preparing a new corporate workstation: computer name, power settings, removal of McAfee and old Office, application installation, a few system tweaks, plus a log and a summary.

> Polish version: [README.md](README.md)

---

## Repository structure

```
/
├── script/
│   ├── Start-Firmowy.bat        # launches the wizard as Administrator
│   └── files/
│       ├── Setup-Firmowy.ps1    # the wizard (GUI)
│       └── apps.json            # list of applications to install
├── build/
│   └── Build-Package.ps1        # builds ZIP/EXE packages
├── .github/workflows/           # CI and automated releases
├── LICENSE
└── README.md / README.en.md
```

Keep the `files\` folder next to `Start-Firmowy.bat`.

---

## Requirements

- Windows 10 / 11 (built-in Windows PowerShell 5.1)
- **Administrator** account
- Installers folder — `C:\instalki\` by default; any other path (including a network share) can be set in the UI or via the `-InstallerPath` parameter

---

## Usage

1. Copy the repository to the machine (or a USB stick).
2. Run **`script\Start-Firmowy.bat`** (it asks for elevation via UAC if needed).
3. Adjust the options in the tabs and click **Uruchom** (Run).

> Do not run the `.ps1` directly — the `.bat` sets elevation, STA mode (required by the GUI) and bypasses ExecutionPolicy for that single process only.

---

## The window

### "Ustawienia" (Settings) tab

| Section | What it does |
|---------|--------------|
| Installers folder | Path to the installers (Browse button); the application list refreshes on change |
| Computer name | Live validation (letters, digits, hyphens, max 15 chars, not digits only); applied after reboot |
| Power | High Performance plan (created from template if missing), screen/sleep = never, hibernation off, screensaver off |
| Pre-install cleanup | Removes McAfee (Antivirus, WebAdvisor + folders) and old Office via Microsoft's official SaRA tool |
| Extra settings | System restore point, time zone + time sync, show file extensions and hidden files, "This PC" desktop icon |
| Install options | Skip already installed apps, **registry verification after install**, **SHA256 check** of installers, optional ESET activation key |
| Extra features | Disable ads and suggestions, **no feedback prompts and tips**, pl-PL region and language, desktop shortcuts, Chrome start page |
| Cleanup | Clean temp files and recycle bin, delete installed installers from the local folder, copy the log to a USB stick |
| At the end | Install Windows updates (with **resume after restart**), open Windows Update, restore ExecutionPolicy (Restricted) |

#### Extra features in detail

- **Ads and suggestions** — turns off suggested apps in Start, lock-screen ads, the advertising ID and automatic installs of promoted apps (current user).
- **No feedback prompts and tips** — feedback frequency = never, no Feedback Hub notifications, Spotlight, Windows tips or the "finish setting up your device" screen (current user; **telemetry is not changed**).
- **Region and language** (off by default) — pl-PL format, Poland location, Polish Programmers keyboard. Replaces the user's language list; full effect after a reboot.
- **Desktop shortcuts** — for all users: Chrome, Word, Excel, Outlook, Adobe Reader (only for installed programs).
- **Chrome** (off by default) — sets the start page via Chrome Enterprise policy in the registry (Chrome will show "managed by your organization").
- **Windows updates** (off by default) — searches, downloads and installs updates through the built-in Windows Update API (no extra modules). Can take long; cannot be cancelled midway.
- **Installer cleanup** — deletes only the files installed in this run, and only from a local drive (never from a USB stick or network share).
- **Log copy** — writes the log to `PrepareWorkstation-logs\` on a USB stick (preferring the one the installers came from).

### Readiness check (button at the bottom)

Before installing it checks: Windows edition (Home cannot join a domain), domain membership, installers, internet, power and battery health, free space, disk health, pending reboot, **other antivirus** (conflicts with ESET), Windows activation, a previous preparation of this PC, and UrBackup server reachability. Errors are also shown in the confirmation dialog before starting.

### "Aplikacje" (Applications) tab

Driven by `apps.json`. For each entry you see whether the installer file is present, whether the app is already installed, and the install mode. Entries without a file are greyed out and unchecked. Buttons: select/deselect all, refresh, **Edytuj apps.json** (edit), **Zapisz sumy SHA256** (save SHA256).

**Installers from a USB stick — no copying to `C:\instalki`:**

- **Drag** installer files, or a whole folder from the stick, onto the window.
- **Dodaj pliki...** (Add files) — a regular file picker (always works).
- **Znajdź na pendrive** (Find on USB) — scans removable drives (up to 3 folder levels).

Files are matched by name against `apps.json` (case-insensitive), checked, and used **directly from the stick** — keep it plugged in until the install finishes. Files matching no app are ignored. The "file" column then shows "dodany ręcznie" (added manually).

> Windows blocks dragging from a normal Explorer into a window running as Administrator. The program tries to work around this; if dragging shows a "no" cursor, use **Dodaj pliki...** or **Znajdź na pendrive**.

### "Odinstaluj" (Uninstall) tab

A list of programs like **Settings → Apps**: registry programs (64/32-bit, including per-user) and Store apps. Search box; columns: version, publisher, size, type, mode. Checked items are uninstalled **before** the new programs are installed.

- Updates (KB), system components, VC++/.NET runtimes and protected Store apps (Store, Windows Security, ...) are hidden by default; **Pokaż także komponenty i aktualizacje** shows them.
- Mode: `cicha (MSI)` and `cicha` run without windows; for `widoczna` the program runs the regular uninstaller and waits until you finish it (it never guesses switches).
- **Zaznacz typowe zbędne** selects known junk: Xbox, Solitaire, Bing, Skype, Clipchamp, promoted games, and among programs McAfee, Norton, WildTangent, Dell/HP/Lenovo OEM tools.
- **Sklep: usuń też dla nowych użytkowników** — the app will not come back on new accounts.

### "Autostart" tab

Programs launched with Windows (Run keys and Startup folders). Checked = **disabled** at startup, like in Task Manager (nothing is deleted); unchecking restores it. Covers all-users (HKLM) entries and the administrator account (HKCU). **Zaznacz typowe zbędne** picks OneDrive, Teams, Spotify, Skype, Discord, etc.

### "Przebieg" (Progress) tab

Live colour-coded log, also written to `C:\ProgramData\PrepareWorkstation\logs\` (the **Folder logów** button opens it).

### Bottom bar

- **Uruchom** — shows the list of steps for confirmation, then runs them with a progress bar.
- **Przerwij** (Cancel) — finishes the current step and stops (never kills an installer mid-way).
- **Tryb testowy** (Dry run) — simulation only: shows what would happen, changes nothing.
- At the end: a summary (OK / skipped / errors) and a reboot prompt if needed.

---

## After preparation: to-do list, restart, marker

- **Manual to-do list** — at the end the program writes `DO-ZROBIENIA-<computer>-<date>.txt` to the **installers folder** (or `C:\ProgramData\PrepareWorkstation\logs\` if it is not writable) and prints it to the log. It contains: join the domain, sign in to Office, activate ESET (if no key was given), the **AnyDesk ID** read from the program, the UrBackup client to add on the server, apps that failed or had no file, updates to repeat, and a restart.
- **UrBackup server** (Applications tab, "Serwer UrBackup (adres IP)" field) — the program checks that the server answers (port 55414) and adds instructions with the IP and computer name to the list. It does **not** write the address into the client: there is no verified silent-configuration method for the Windows client (on a LAN the server usually discovers the client itself).
- **Resume after restart** — if Windows updates require a restart and steps remain, the program asks whether to restart and finish. It saves state to `C:\ProgramData\PrepareWorkstation\resume.json` (without the ESET key) and registers the scheduled task `PrepareWorkstation-Resume` (at logon, elevated). After sign-in it asks for confirmation, removes the task and finishes the plan. Works for accounts in the Administrators group. For the `.exe`, the app must accept the `-Resume` parameter.
- **"Computer prepared" marker** — after a run it stores the program version, date and the list of completed steps in `HKLM\SOFTWARE\PrepareWorkstation`. On the next run it warns that the computer was already prepared.
- **Service verification** — for apps with a `service` field in `apps.json` (ESET: `ekrn`, AnyDesk, UrBackup) the program checks after install that the service is running.

---

## Installers folder

Default file names (changeable in `apps.json`):

| File | Application | Mode | Download |
|------|-------------|------|----------|
| `AnyDesk.exe` | AnyDesk | silent | https://anydesk.com/en/downloads/windows |
| `ees_nt64.msi` | ESET Endpoint Security | silent (MSI) | https://www.eset.com/int/business/download/endpoint-security/ |
| `googlechromestandaloneenterprise64.msi` | Google Chrome Enterprise | silent (MSI) | https://enterprise.google.com/chrome/chrome-browser/ |
| `Intel-Driver-and-Support-Assistant-Installer.exe` | Intel Driver & Support Assistant | silent | https://www.intel.com/content/www/us/en/support/detect.html |
| `OfficeSetup32bitPL.exe` | Microsoft Office 32-bit PL | manual | https://www.microsoft.com/pl-pl/microsoft-365/get-started-with-office-2021 |
| `AdobeReader_PL.exe` | Adobe Acrobat Reader PL (offline) | silent | https://get.adobe.com/reader/enterprise/ |
| `UrBackup_Client.exe` | UrBackup Client (x86/x64) | silent, `/S` | https://www.urbackup.org/download.html#client_windows |

> 32-bit Office on a 64-bit OS: the wizard asks for confirmation before launching the installer.

---

## Adding applications — `apps.json`

No script editing needed. Add an object to `script\files\apps.json` (or click **Edytuj apps.json**) and **Odśwież listę** (refresh):

```json
{
  "id": "vlc",
  "name": "VLC media player",
  "file": "vlc-3.0.21-win64.exe",
  "type": "exe",
  "args": "/L=1033 /S",
  "detect": "^VLC media player",
  "default": false
}
```

| Field | Meaning |
|-------|---------|
| `id` | unique id (`eset` gets special handling for the activation key) |
| `name` | display name |
| `file` | file name inside the installers folder |
| `type` | `exe` (silent), `msi` (run through `msiexec /qn /i`), `manual` (opens the installer and waits) |
| `args` | installer arguments (for `msi`, appended after `/qn /i "file" /norestart`) |
| `detect` | regex matched against names in "Apps & features" — used to skip already installed apps |
| `default` | whether it is checked by default |
| `warn32on64` | (optional) warn for 32-bit installers on 64-bit systems |
| `sha256` | (optional) installer checksum — see below |
| `service` | (optional) Windows service name checked after install (waits up to 20 s for it to run) |

### Installer SHA256 checksums

Click **Zapisz sumy SHA256** on the Applications tab (with known-good files) to store their hashes in `apps.json`. From then on, with the "Sprawdzaj sumy SHA256" option on, the program refuses to install a file with a different hash (corrupted, tampered, or a newer version — then save the hashes again). Apps without a hash install as before.

---

## ESET activation

Enter the key in the **ESET key** field (Settings → Install options). It is passed to the installer as `ACTIVATION_DATA=key:...` and is never written to the log or to disk.

---

## Releases and packages

Ready-made packages are on the **Releases** page on GitHub:

| File | Contents |
|------|----------|
| `PrepareWorkstation-<version>.zip` | `Start-Firmowy.bat` + `files\` (script and `apps.json`) + `instalki-template` folder template + README |
| `PrepareWorkstation-exe-<version>.zip` | `Prepare-Workstation.exe` (standalone, requires admin) + `apps.json` next to the `.exe` + template + README |
| `SHA256SUMS.txt` | checksums — verify with `Get-FileHash file.zip` |

> The `.exe` is not code-signed, so SmartScreen or an antivirus may flag it. The script version (`.bat` + `.ps1`) is transparent and does not have this problem.

Build locally (output in `dist\`):

```powershell
pwsh -File build\Build-Package.ps1 -Version 1.0.0            # ZIP only
powershell -File build\Build-Package.ps1 -Version 1.0.0 -WithExe   # ZIP + EXE (Windows)
```

A new release is created automatically when a version tag is pushed: `git tag v1.0.0 && git push origin v1.0.0` (workflow `.github/workflows/release.yml`). The `ci.yml` workflow validates script syntax and `apps.json` on every push.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| The window does not appear | Launch via `Start-Firmowy.bat`. The PowerShell console is hidden; fatal errors show in a dialog. Details in `C:\ProgramData\PrepareWorkstation\logs\` |
| App shows "BRAK" (missing) in the file column | The file name must match `apps.json` (case-insensitive) |
| No access to a network share | Check in PowerShell: `Test-Path \\server\installers`. Note: mapped drives can be invisible after UAC elevation — use a UNC path |
| ESET installation error | Make sure the previous antivirus is fully removed (reboot if needed) |
| Adobe won't install silently | Use the **offline** installer from https://get.adobe.com/reader/enterprise/ |
| 32-bit Office blocked on 64-bit OS | Use the 64-bit installer and update `file` in `apps.json` |
| Office won't install after removal | Reboot after SaRA, then run again |
| McAfee not fully removed | Some versions need McAfee's MCPR tool |
| Restore point not created | Enable System Protection for C:. Windows allows one restore point per 24 hours by default |
| Screensaver/icon tweaks hit the wrong user | "HKCU" settings apply to the account used for elevation. If UAC asks for another admin's credentials, they land in that profile |

---

## Note: removed uninstaller

Earlier versions shipped `Deinstalator.ps1` for cleaning test machines. It was removed from the repository (it remains in git history). The McAfee / old Office cleanup stays in the wizard as a pre-install step.

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).
