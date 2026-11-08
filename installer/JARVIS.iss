#define MyAppName "JARVIS Assistant"
#define MyAppVersion "1.2.2"
#define MyAppPublisher "JARVIS Assistant"
#define MyAppExeName "JARVIS.exe"

[Setup]
AppId={{EFD802AC-8A2D-4F6A-B11D-8B102193FC0F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\JARVIS Assistant
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist-installer
OutputBaseFilename=JARVIS-Assistant-Setup-{#MyAppVersion}-x64
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Personal desktop AI assistant
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные задачи:"; Flags: unchecked

[Files]
Source: "..\dist\JARVIS.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\JARVIS Assistant"; Filename: "{app}\JARVIS.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\JARVIS Assistant"; Filename: "{app}\JARVIS.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\JARVIS.exe"; Description: "Запустить JARVIS Assistant"; Flags: postinstall nowait skipifsilent
