; Inno Setup script for the Caller's Compendium Windows installer.
;
; This produces an UNSIGNED installer (this release wave ships no code-signing;
; see ADR-002 §6). Values that vary per build are passed on the ISCC command
; line with /D defines; the fallbacks below let the script compile locally for a
; quick smoke test.
;
;   iscc /DMyAppVersion=0.1.0 ^
;        /DSourceDir="..\..\app\build\windows\x64\runner\Release" ^
;        /DOutputDir="..\..\dist" ^
;        /DOutputBaseName="CallersCompendium-0.1.0-windows-x64" ^
;        packaging\windows\CallersCompendium.iss

#define MyAppName "Caller's Compendium"
#define MyAppExeName "compendium_app.exe"
#define MyAppPublisher "Caller's Compendium contributors"
#define MyAppURL "https://github.com/ibanner56/CallersCompendium"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef OutputBaseName
  #define OutputBaseName "CallersCompendium-setup"
#endif
#define IconFile "..\..\app\windows\runner\resources\app_icon.ico"

[Setup]
; A stable, app-specific AppId so upgrades replace the prior install in place.
AppId={{3FE2B4AC-BD76-4B77-A2B5-D77E45D17651}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\Caller's Compendium
DefaultGroupName=Caller's Compendium
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
SetupIconFile={#IconFile}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 64-bit-only app: install under Program Files (not the x86 folder). `x64`
; compiles on every Inno Setup 6.x (x64compatible needs 6.3+).
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Allow a per-user install without elevation if the user chooses.
PrivilegesRequiredOverridesAllowed=dialog
; The [Registry] entries below register the .ccshare file type; this tells
; Explorer to pick them up at the end of setup and uninstall.
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "danish"; MessagesFile: "compiler:Languages\Danish.isl"
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
; The .ccshare file type (PLAT-3). Double-clicking one starts the app with the
; path as its only argument; a running app is asked to open it instead. HKA is
; HKLM for an all-users install and HKCU for a per-user one. The app checks the
; path and only ever opens import review with it.
; tools/release/test_windows_file_association.py pins these entries.
Root: HKA; Subkey: "Software\Classes\.ccshare"; ValueType: string; ValueName: ""; ValueData: "CallersCompendium.Share"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.ccshare\OpenWithProgids"; ValueType: string; ValueName: "CallersCompendium.Share"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\CallersCompendium.Share"; ValueType: string; ValueName: ""; ValueData: "Caller's Compendium share file"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\CallersCompendium.Share\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\CallersCompendium.Share\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
