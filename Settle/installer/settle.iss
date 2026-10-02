; Установщик Settle для Windows (Inno Setup 6.3+).
; Обычно собирается через build_installer.ps1 — он подставляет версию из pubspec.yaml
; и пути ниже. Значения по умолчанию позволяют открыть скрипт и в Inno Setup Compiler.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
; Папка с msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll (Visual C++ runtime).
#ifndef CrtDir
  #define CrtDir "C:\Windows\System32"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\installer"
#endif

#define AppName "Settle"
#define AppExeName "Settle.exe"
#define AppPublisher "mrgsdev"
; Прежнее название: при обновлении убираем его exe и ярлыки.
#define OldAppName "Кагиз Трахи"
#define OldExeName "kagiz_trakhi.exe"

[Setup]
; AppId идентифицирует приложение для обновлений и удаления — не менять
; (он же у версий под прежним названием, поэтому Settle ставится поверх них).
AppId={{3C1ABAD6-A24E-42AC-93D9-1D29C150718B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/mrgsdev
AppSupportURL=https://github.com/mrgsdev
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription=Установка {#AppName}
; Папка по умолчанию; пользователь выбирает свою на странице «Выбор папки установки».
DefaultDirName={autopf}\Settle
; Страница выбора папки показывается всегда, в том числе при обновлении.
DisableDirPage=no
DisableProgramGroupPage=yes
; По умолчанию — установка для текущего пользователя без прав администратора;
; в диалоге можно выбрать установку для всех пользователей (Program Files).
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Settle-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Закрыть запущенное приложение перед обновлением.
CloseApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Убрать ресурсы предыдущей версии, чтобы не оставались устаревшие файлы.
; Данные пользователя хранятся отдельно (%APPDATA%) и не затрагиваются.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\{#OldExeName}"
Type: files; Name: "{autoprograms}\{#OldAppName}.lnk"
Type: files; Name: "{autodesktop}\{#OldAppName}.lnk"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.lib,*.exp,*.ilk"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#CrtDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CrtDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CrtDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Можно ли создать папку установки: пробуем создать временную папку
// в ближайшей существующей родительской папке.
function CanCreateIn(Dir: String): Boolean;
var
  Parent, Probe: String;
begin
  Dir := RemoveBackslash(Dir);
  while not DirExists(Dir) do
  begin
    Parent := RemoveBackslash(ExtractFileDir(Dir));
    if (Parent = '') or (Parent = Dir) then Break;
    Dir := Parent;
  end;
  Probe := AddBackslash(Dir) + '~settle-' + GetDateTimeString('hhnnsszzz', #0, #0);
  Result := CreateDir(Probe);
  if Result then RemoveDir(Probe);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Msg: String;
begin
  Result := True;
  if (CurPageID = wpSelectDir) and not CanCreateIn(WizardDirValue) then
  begin
    Msg := 'Нет прав на запись в папку:' + #13#10 + WizardDirValue + #13#10#13#10 + 'Выберите другую папку';
    if not IsAdminInstallMode then
      Msg := Msg + ' или запустите установку заново и выберите «Установить для всех пользователей»';
    SuppressibleMsgBox(Msg + '.', mbError, MB_OK, IDOK);
    Result := False;
  end;
end;

// При обновлении в другую папку удаляем прежнюю копию, чтобы не осталось двух установок.
// Данные пользователя (%APPDATA%) деинсталлятор не трогает.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Key, OldDir, Uninstaller: String;
  Code: Integer;
begin
  if CurStep <> ssInstall then Exit;
  Key := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1');
  if not RegQueryStringValue(HKA, Key, 'Inno Setup: App Path', OldDir) then Exit;
  if CompareText(RemoveBackslash(OldDir), RemoveBackslash(ExpandConstant('{app}'))) = 0 then Exit;
  if RegQueryStringValue(HKA, Key, 'UninstallString', Uninstaller) then
    Exec(RemoveQuotes(Uninstaller), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE,
      ewWaitUntilTerminated, Code);
end;
