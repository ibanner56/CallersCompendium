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

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
