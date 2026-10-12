#ifndef AppVersion
  #error AppVersion must come from VERSION via build.ps1
#endif

[Setup]
AppId={{8E6A5C4D-7825-4A66-8348-243C69337907}
AppName=SearcheXtra
AppVersion={#AppVersion}
AppPublisher=small32
AppPublisherURL=https://github.com/small32/SearcheXtra
DefaultDirName={localappdata}\Programs\SearcheXtra
DefaultGroupName=SearcheXtra
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.17763
OutputDir=..\artifacts
OutputBaseFilename=SearcheXtra-{#AppVersion}-win-x64-setup
SetupIconFile=..\SearcheXtra\AppIcon.ico
UninstallDisplayIcon={app}\AppIcon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardImageFile=WizardIcon.png
WizardSmallImageFile=WizardSmallIcon.png
WizardImageStretch=no
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\artifacts\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "check-runtime.ps1"; Flags: dontcopy

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Icons]
Name: "{group}\SearcheXtra"; Filename: "{app}\SearcheXtra.exe"; IconFilename: "{app}\AppIcon.ico"; IconIndex: 0
Name: "{autodesktop}\SearcheXtra"; Filename: "{app}\SearcheXtra.exe"; IconFilename: "{app}\AppIcon.ico"; IconIndex: 0; Tasks: desktopicon

[Run]
Filename: "{app}\SearcheXtra.exe"; Description: "{cm:LaunchProgram,SearcheXtra}"; Flags: nowait postinstall skipifsilent

[Code]
var
  DependencyRestart: Boolean;

function RuntimeInstalled(Name: String): Boolean;
var
  ExitCode: Integer;
begin
  ExitCode := -1;
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\check-runtime.ps1') + '" ' + Name,
    '', SW_HIDE, ewWaitUntilTerminated, ExitCode) and (ExitCode = 0);
  Log(Name + ' detection exit code: ' + IntToStr(ExitCode));
  if ExitCode = 2 then
    RaiseException('Unable to check ' + Name + '. See the installer log.');
end;

procedure InstallRuntime(Name, Url, FileName, Hash, Arguments: String; Elevate: Boolean);
var
  ExitCode: Integer;
  Started: Boolean;
  Installer: String;
  SignaturePath: String;
begin
  if RuntimeInstalled(Name) then exit;
  WizardForm.StatusLabel.Caption := 'Downloading ' + Name + '...';
  DownloadTemporaryFile(Url, FileName, Hash, nil);
  Installer := ExpandConstant('{tmp}\') + FileName;
  { Evergreen changes its bootstrapper: validate the Microsoft signature instead of pinning its hash. }
  if Hash = '' then begin
    SignaturePath := Installer;
    StringChangeEx(SignaturePath, '''', '''''', True);
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -NonInteractive -Command "$s=Get-AuthenticodeSignature -LiteralPath ''' + SignaturePath + '''; if ($s.Status -eq ''Valid'' -and $s.SignerCertificate.Subject -match ''O=Microsoft Corporation'') {exit 0} else {exit 1}"',
      '', SW_HIDE, ewWaitUntilTerminated, ExitCode) or (ExitCode <> 0) then
      RaiseException('Invalid Microsoft installer signature: ' + Name);
  end;
  WizardForm.StatusLabel.Caption := 'Installing ' + Name + '...';
  ExitCode := -1;
  if Elevate then
    Started := ShellExec('runas', Installer, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ExitCode)
  else
    Started := Exec(Installer, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  Log(Name + ' installation exit code: ' + IntToStr(ExitCode));
  if not Started or ((ExitCode <> 0) and (ExitCode <> 3010)) then
    RaiseException('Cannot install ' + Name + ' (code ' + IntToStr(ExitCode) + ').');
  if ExitCode = 3010 then DependencyRestart := True
  else if not RuntimeInstalled(Name) then
    RaiseException(Name + ' is still unavailable after installation.');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  try
    ExtractTemporaryFile('check-runtime.ps1');
    InstallRuntime('DotNet',
      'https://builds.dotnet.microsoft.com/dotnet/Runtime/8.0.31/dotnet-runtime-8.0.31-win-x64.exe',
      'dotnet-runtime.exe', '249b0d10d4bfa8ec8ded5e6e220e871e71cca89290f1a2fdb93ca59abb8ff97b',
      '/install /quiet /norestart', True);
    InstallRuntime('AppSdk',
      'https://aka.ms/windowsappsdk/1.8/1.8.260921001/windowsappruntimeinstall-x64.exe',
      'windowsappruntime.exe', '7c092e85fc1e3e7cb2bd7d549aaab03caf924131f15d9b20b1855457a98205aa',
      '--quiet', False);
    InstallRuntime('WebView2', 'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
      'webview2setup.exe', '', '/silent /install', False);
  except
    Result := GetExceptionMessage;
  end;
end;

function NeedRestart(): Boolean;
begin
  Result := DependencyRestart;
end;
