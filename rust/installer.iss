; Hydride Inno Setup 安装脚本
; 功能：双语（默认跟随系统语言）/ 版本比较 / Silanes 服务注册与卸载 / 不创建开始菜单快捷方式

#define MyAppName "Hydride"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Copyright (C) 2026 NXRKYMANE SOFTWARE"
#define MyAppURL "https://github.com/NXRKYMANE/Hydride"
#define MyAppExeName "hydride_svc64.exe"

[Setup]
AppId={{8F3C2E1A-9D4B-4C6E-B7F2-5A1E8D0C3B64}
AppName=Hydride v{#MyAppVersion}
AppVersion={#MyAppVersion}
AppVerName=Hydride v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Hydride
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=publish
OutputBaseFilename=hydride-svc-win-x64-setup-v{#MyAppVersion}
SetupIconFile=..\misc\Proj.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=classic
DisableWelcomePage=no
WizardImageFile=..\misc\Background.bmp
WizardSmallImageFile=..\misc\Rust.bmp
CloseApplications=yes
DisableDirPage=no
DirExistsWarning=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName=Hydride System Memory Manager Service
VersionInfoProductVersion={#MyAppVersion}.0
VersionInfoCompany=NXRKYMANE SOFTWARE
VersionInfoCopyright={#MyAppPublisher}
VersionInfoDescription=Hydride Installer

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[CustomMessages]
english.SilanesNotFound=Silanes is required but not found. Please install Silanes from https://github.com/NXRKYMANE/Silanes before installing Hydride.
chinesesimp.SilanesNotFound=未找到 Silanes。%n请先安装 Silanes: https://github.com/NXRKYMANE/Silanes 再安装 Hydride。
english.SameVersionPrompt=An identical version (v%1) is already installed. Reinstall?
chinesesimp.SameVersionPrompt=已安装相同版本的 Hydride (v%1)。是否重新安装？
english.DowngradePrompt=A newer version (v%1) is already installed. Downgrade to v{#MyAppVersion}?
chinesesimp.DowngradePrompt=已安装更新的版本 (v%1)。降级到 v{#MyAppVersion}？
english.RegisterFail=Failed to register service.%n%n%1%n%nAbort: exit setup  |  Retry: try again  |  Ignore: skip and continue
chinesesimp.RegisterFail=注册服务失败。%n%n%1%n%n「终止」退出安装  「重试」重新注册  「忽略」跳过并继续
english.StartFail=Failed to start service.%n%n%1%n%nAbort: exit setup  |  Retry: try again  |  Ignore: skip and continue
chinesesimp.StartFail=启动服务失败。%n%n%1%n%n「终止」退出安装  「重试」重新启动  「忽略」跳过并继续
english.DeleteFail=Failed to delete service.%n%n%1%n%nAbort: exit uninstall  |  Retry: try again  |  Ignore: skip and continue
chinesesimp.DeleteFail=删除服务失败。%n%n%1%n%n「终止」退出卸载  「重试」重新尝试  「忽略」跳过并继续
english.NoOutput=(no output captured; exit code %1)
chinesesimp.NoOutput=（未捕获到输出；退出码 %1）
english.ViewDoc=View Documentation
chinesesimp.ViewDoc=查看中文文档
english.PathTooLong=The selected installation folder is too long (%1 characters) and may cause the service registration to fail. Continue anyway?
chinesesimp.PathTooLong=所选安装文件夹路径过长（%1 个字符），可能导致服务注册失败。仍要继续吗？

[Files]
Source: "publish\hydride_svc64.exe"; DestDir: "{app}"; Flags: ignoreversion; AfterInstall: LogFile('{app}\hydride_svc64.exe')
Source: "..\misc\Proj.ico"; DestDir: "{app}"; DestName: "icon.ico"; Flags: ignoreversion; AfterInstall: LogFile('{app}\icon.ico')
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: recursesubdirs createallsubdirs ignoreversion; AfterInstall: LogFile('{app}\docs\')
Source: "..\libs\*"; DestDir: "{app}\libs"; Flags: recursesubdirs createallsubdirs ignoreversion; AfterInstall: LogFile('{app}\libs\')

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\hydride_svc64.exe"; ValueType: string; ValueName: ""; ValueData: "{app}\hydride_svc64.exe"; Flags: uninsdeletekey

[Run]
Filename: "{code:GetDocPath}"; Description: "{cm:ViewDoc}"; Flags: postinstall nowait skipifsilent unchecked shellexec

[Code]
const
  // 注意：Pascal 字符串中 { 不需要写 {{，写 {{ 会原样保留（实测）
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F3C2E1A-9D4B-4C6E-B7F2-5A1E8D0C3B64}_is1';
  // NSIS 旧版安装的卸载键（兼容从 NSIS 安装包升级）
  NSISUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Hydride';
  SilanesKey = 'Software\Microsoft\Windows\CurrentVersion\App Paths\silanes64.exe';

var
  // 安装页与准备页的滚动日志面板（模拟 NSIS 的 DetailPrint）
  LogMemo: TNewMemo;
  PrepLogMemo: TNewMemo;
  // 准备页进度条（Inno 7 已移除 PreparingGauge 属性，自行创建）
  PrepGauge: TNewProgressBar;
  // 按钮行左侧的版权文本
  CopyrightLabel: TNewStaticText;

// ── 安装页日志：追加一行并滚动到底部（写入两个页面）──
// SelLength 清零后再设 SelStart；WM_VSCROLL(SB_BOTTOM) 不依赖焦点，保证滚到底
procedure AddLog(const Msg: String);
begin
  if Msg = '' then
    Exit;
  if LogMemo <> nil then
  begin
    SendMessage(LogMemo.Handle, $000B {EM_SETREDRAW}, 0, 0);
    LogMemo.Lines.Add(Msg);
    LogMemo.SelLength := 0;
    LogMemo.SelStart := Length(LogMemo.Text);
    SendMessage(LogMemo.Handle, $00B7 {EM_SCROLLCARET}, 0, 0);
    SendMessage(LogMemo.Handle, $0115 {WM_VSCROLL}, 7 {SB_BOTTOM}, 0);
    SendMessage(LogMemo.Handle, $000B {EM_SETREDRAW}, 1, 0);
  end;
  if PrepLogMemo <> nil then
  begin
    SendMessage(PrepLogMemo.Handle, $000B {EM_SETREDRAW}, 0, 0);
    PrepLogMemo.Lines.Add(Msg);
    PrepLogMemo.SelLength := 0;
    PrepLogMemo.SelStart := Length(PrepLogMemo.Text);
    SendMessage(PrepLogMemo.Handle, $00B7 {EM_SCROLLCARET}, 0, 0);
    SendMessage(PrepLogMemo.Handle, $0115 {WM_VSCROLL}, 7 {SB_BOTTOM}, 0);
    SendMessage(PrepLogMemo.Handle, $000B {EM_SETREDRAW}, 1, 0);
  end;
end;

// [Files] 条目安装完成后的回调，按 NSIS 的 "Extract: <完整路径>" 格式记录
procedure LogFile(const TargetPath: String);
begin
  AddLog('Extract: ' + ExpandConstant(TargetPath));
end;

// ── 创建滚动日志面板（安装页 + 准备页，均位于进度条下方）──
procedure InitializeWizard;
var
  AnchorTop, LogHeight: Integer;
begin
  // 安装页日志框（ssNone 隐藏滚动条，bsSingle 为 Win10 扁平边框）
  LogMemo := TNewMemo.Create(WizardForm);
  LogMemo.Parent := WizardForm.InstallingPage;
  LogMemo.ReadOnly := True;
  LogMemo.ScrollBars := ssNone;
  LogMemo.BorderStyle := bsSingle;
  LogMemo.WantTabs := True;
  LogMemo.Color := clWhite;
  LogMemo.Font.Name := 'Cascadia Code';
  LogMemo.Font.Size := 9;

  // 以进度条与状态文本中较低者为锚点，确保日志框始终在它们下方
  if WizardForm.StatusLabel.Top > WizardForm.ProgressGauge.Top then
    AnchorTop := WizardForm.StatusLabel.Top + WizardForm.StatusLabel.Height
  else
    AnchorTop := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height;

  LogHeight := WizardForm.InstallingPage.ClientHeight - AnchorTop - 20;
  if LogHeight < 0 then
    LogHeight := 0;

  LogMemo.SetBounds(
    WizardForm.ProgressGauge.Left,
    AnchorTop + 8,
    WizardForm.ProgressGauge.Width,
    LogHeight);

  // 准备页进度条 + 日志框（与安装页同坐标，切换页面无跳动）
  PrepGauge := TNewProgressBar.Create(WizardForm);
  PrepGauge.Parent := WizardForm.PreparingPage;
  PrepGauge.Style := npbstMarquee;
  PrepGauge.SetBounds(
    WizardForm.ProgressGauge.Left,
    WizardForm.ProgressGauge.Top,
    WizardForm.ProgressGauge.Width,
    WizardForm.ProgressGauge.Height);

  PrepLogMemo := TNewMemo.Create(WizardForm);
  PrepLogMemo.Parent := WizardForm.PreparingPage;
  PrepLogMemo.ReadOnly := True;
  PrepLogMemo.ScrollBars := ssNone;
  PrepLogMemo.BorderStyle := bsSingle;
  PrepLogMemo.WantTabs := True;
  PrepLogMemo.Color := clWhite;
  PrepLogMemo.Font.Name := 'Cascadia Code';
  PrepLogMemo.Font.Size := 9;
  PrepLogMemo.SetBounds(LogMemo.Left, LogMemo.Top, LogMemo.Width, LogMemo.Height);

  // 准备就绪页的目录摘要列表：同样隐藏滚动条并改用扁平边框
  WizardForm.ReadyMemo.ScrollBars := ssNone;
  WizardForm.ReadyMemo.BorderStyle := bsSingle;
  WizardForm.ReadyMemo.Color := clWhite;

  // 按钮行左侧的版权文本（与按钮垂直居中，不覆盖按钮区）
  CopyrightLabel := TNewStaticText.Create(WizardForm);
  CopyrightLabel.Parent := WizardForm;
  CopyrightLabel.Caption := '{#MyAppPublisher}';
  CopyrightLabel.Font.Size := 8;
  CopyrightLabel.Font.Color := clGray;
  CopyrightLabel.AutoSize := True;
  CopyrightLabel.Top := WizardForm.CancelButton.Top + (WizardForm.CancelButton.Height - CopyrightLabel.Height) div 2;
  CopyrightLabel.Left := 35;
end;

// ── 页面切换时补设样式：Inno 7 的页面控件按需创建，懒创建的控件需在此重设 ──
// 进入含日志框的页面时把焦点移到按钮上，避免日志框获得焦点导致光标闪烁
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpReady then
  begin
    WizardForm.ReadyMemo.ScrollBars := ssNone;
    WizardForm.ReadyMemo.BorderStyle := bsSingle;
    WizardForm.ReadyMemo.Color := clWhite;
  end
  else if CurPageID = wpPreparing then
  begin
    PrepLogMemo.ScrollBars := ssNone;
    PrepLogMemo.BorderStyle := bsSingle;
    // 隐藏准备页内置描述文本，避免被日志框遮挡后从边缘漏字
    WizardForm.PreparingLabel.Visible := False;
    // WM_NEXTDLGCTL(wParam=句柄)：把焦点交给指定控件（Inno 脚本未暴露 SetFocus）
    if WizardForm.NextButton.Visible and WizardForm.NextButton.Enabled then
      SendMessage(WizardForm.Handle, $0028 {WM_NEXTDLGCTL}, WizardForm.NextButton.Handle, 0)
    else if WizardForm.CancelButton.Visible and WizardForm.CancelButton.Enabled then
      SendMessage(WizardForm.Handle, $0028 {WM_NEXTDLGCTL}, WizardForm.CancelButton.Handle, 0);
  end
  else if CurPageID = wpInstalling then
  begin
    LogMemo.ScrollBars := ssNone;
    LogMemo.BorderStyle := bsSingle;
    if WizardForm.NextButton.Visible and WizardForm.NextButton.Enabled then
      SendMessage(WizardForm.Handle, $0028 {WM_NEXTDLGCTL}, WizardForm.NextButton.Handle, 0)
    else if WizardForm.CancelButton.Visible and WizardForm.CancelButton.Enabled then
      SendMessage(WizardForm.Handle, $0028 {WM_NEXTDLGCTL}, WizardForm.CancelButton.Handle, 0);
  end;
end;

// ── 版本比较：V1>V2 → 1, V1=V2 → 0, V1<V2 → -1 ──
function CompareVersions(const V1, V2: String): Integer;
var
  A1, A2: String;
  P1, P2, C1, C2: Integer;
begin
  A1 := V1;
  A2 := V2;
  while True do
  begin
    P1 := Pos('.', A1);
    P2 := Pos('.', A2);
    if P1 = 0 then
      C1 := StrToIntDef(A1, 0)
    else
    begin
      C1 := StrToIntDef(Copy(A1, 1, P1 - 1), 0);
      A1 := Copy(A1, P1 + 1, MaxInt);
    end;
    if P2 = 0 then
      C2 := StrToIntDef(A2, 0)
    else
    begin
      C2 := StrToIntDef(Copy(A2, 1, P2 - 1), 0);
      A2 := Copy(A2, P2 + 1, MaxInt);
    end;
    if C1 < C2 then
    begin
      Result := -1;
      Exit;
    end;
    if C1 > C2 then
    begin
      Result := 1;
      Exit;
    end;
    if P1 = 0 then
    begin
      if P2 = 0 then
        Result := 0
      else if StrToIntDef(A2, 0) > 0 then
        Result := -1
      else
        Result := 0;
      Exit;
    end;
    if P2 = 0 then
    begin
      if StrToIntDef(A1, 0) > 0 then
        Result := 1
      else
        Result := 0;
      Exit;
    end;
  end;
end;

// ── 等待旧服务进程完全退出（最长 4 秒），避免覆盖运行中的 exe ──
procedure WaitForOldProcess;
var
  I, J: Integer;
  Output: TExecOutput;
  ResultCode: Integer;
  Found: Boolean;
begin
  I := 0;
  while I < 8 do
  begin
    Found := False;
    if ExecAndCaptureOutput('tasklist.exe', '/FI "IMAGENAME eq hydride_svc64.exe" /FO CSV /NH', '', SW_HIDE, ewWaitUntilTerminated, ResultCode, Output) then
    begin
      for J := 0 to GetArrayLength(Output.StdOut) - 1 do
      begin
        if Pos('hydride_svc64.exe', Output.StdOut[J]) > 0 then
          Found := True;
      end;
    end;
    if not Found then
      Exit;
    Sleep(500);
    I := I + 1;
  end;
end;

// ── 构建错误详情：合并 stdout/stderr 全部行 + 退出码 + 命令行 ──
function BuildErrorText(const Args: String; const ResultCode: Integer; const Output: TExecOutput): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Output.StdErr) - 1 do
    Result := Result + Output.StdErr[I] + #13#10;
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
    Result := Result + Output.StdOut[I] + #13#10;
  Result := TrimRight(Result);
  if Result = '' then
    Result := FmtMessage(CustomMessage('NoOutput'), [IntToStr(ResultCode)]);
  Result := Result + #13#10 + 'Command: ' + Args;
end;

// ── 静默执行 silanes 命令（不弹窗），失败时返回错误文本；输出同时追加到日志框 ──
function SilanesExec(const Args: String; var ErrText: String): Boolean;
var
  SilanesPath: String;
  Output: TExecOutput;
  ResultCode: Integer;
  I: Integer;
begin
  Result := False;
  ErrText := '';
  if RegQueryStringValue(HKLM, SilanesKey, '', SilanesPath) then
  begin
    // 注意：ExecAndCaptureOutput 的 Filename 不能带引号，否则进程启动失败（error 87）
    if ExecAndCaptureOutput(SilanesPath, Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode, Output) and (ResultCode = 0) then
      Result := True
    else
      ErrText := BuildErrorText(Args, ResultCode, Output);

    // 将 silanes 的实际输出逐行显示到 detail 日志框
    for I := 0 to GetArrayLength(Output.StdErr) - 1 do
      if Trim(Output.StdErr[I]) <> '' then
        AddLog(Output.StdErr[I]);
    for I := 0 to GetArrayLength(Output.StdOut) - 1 do
      if Trim(Output.StdOut[I]) <> '' then
        AddLog(Output.StdOut[I]);
  end;
end;

// ── 通过 Silanes 执行命令，失败弹「终止 / 重试 / 忽略」并显示完整错误流 ──
function RunSilanesCommand(const Args, FailMsg: String): Boolean;
var
  ErrText: String;
begin
  Result := False;
  while True do
  begin
    if SilanesExec(Args, ErrText) then
    begin
      Result := True;
      Exit;
    end;
    case MsgBox(FmtMessage(FailMsg, [ErrText]), mbError, MB_ABORTRETRYIGNORE) of
      IDABORT:
        begin
          Result := False;
          Exit;
        end;
      IDIGNORE:
        begin
          Result := True;
          Exit;
        end;
    end;
  end;
end;

// ── 写入包含正确安装路径的服务 YAML 配置 ──
procedure CreateServiceYaml;
var
  YamlPath: String;
begin
  YamlPath := ExpandConstant('{app}\libs\hydride_svc64.yaml');
  SaveStringToFile(YamlPath,
    'service_name: hydride_svc64' + #13#10 +
    'service_display_name: Hydride System Memory Manager Service' + #13#10 +
    'service_description: Automatically manages system memory usage' + #13#10 +
    'service_executable_path: ' + ExpandConstant('{app}\hydride_svc64.exe') + #13#10,
    False);
end;

// ── 安装初始化：版本检测（同版本询问 / 降级警告，兼容 Inno 与 NSIS 旧版）──
// 点「是」后直接继续安装：不运行旧版卸载器（避免长时间等待），
// 旧服务/进程由 PrepareToInstall 统一清理，文件为覆盖式复制
function InitializeSetup(): Boolean;
var
  OldVer: String;
  Cmp: Integer;
begin
  Result := True;

  // 检测已安装版本（Inno 键优先，NSIS 旧版键其次）
  if RegQueryStringValue(HKLM, UninstallKey, 'DisplayVersion', OldVer) or
     RegQueryStringValue(HKLM, NSISUninstallKey, 'DisplayVersion', OldVer) then
  begin
    Cmp := CompareVersions('{#MyAppVersion}', OldVer);
    if Cmp = 0 then
    begin
      // 相同版本：询问是否重装
      if MsgBox(FmtMessage(CustomMessage('SameVersionPrompt'), [OldVer]), mbConfirmation, MB_YESNO) <> IDYES then
        Result := False;
    end
    else if Cmp < 0 then
    begin
      // 旧版本：降级警告
      if MsgBox(FmtMessage(CustomMessage('DowngradePrompt'), [OldVer]), mbConfirmation, MB_YESNO) <> IDYES then
        Result := False;
    end;
    // Cmp > 0（新版本升级）：直接继续，无需确认
  end;
end;

// ── 目录选择页防护：路径过长（>220 字符）时 yaml/exe 路径会触及 MAX_PATH
// 限制导致服务注册失败，提前询问，避免装到一半才报错
function NextButtonClick(CurPageID: Integer): Boolean;
var
  AppLen: Integer;
  SilanesPath: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    AppLen := Length(ExpandConstant('{app}'));
    if AppLen > 220 then
      Result := MsgBox(FmtMessage(CustomMessage('PathTooLong'), [IntToStr(AppLen)]), mbConfirmation, MB_YESNO) = IDYES;
  end
  else if CurPageID = wpReady then
  begin
    // 前置检查：Silanes 未安装时在此直接报错并停留，
    // 避免进入准备页后日志框遮挡内置描述文本导致漏字
    if not RegQueryStringValue(HKLM, SilanesKey, '', SilanesPath) then
    begin
      MsgBox(CustomMessage('SilanesNotFound'), mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// ── 安装前清理：PrepareToInstall 在文件复制前调用 ──
// 停止旧服务并终止所有 hydride_svc64.exe 进程（含手动运行的实例），
// 避免 [Files] 覆盖 {app}\hydride_svc64.exe 时文件被锁定（拒绝访问）
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  SilanesPath: String;
  DummyErr: String;
  Output: TExecOutput;
  ResultCode: Integer;
  OldDir: String;
begin
  Result := '';

  // 1. 前置检查：Silanes
  if not RegQueryStringValue(HKLM, SilanesKey, '', SilanesPath) then
  begin
    Result := CustomMessage('SilanesNotFound');
    Exit;
  end;

  // 2. 删除旧服务（停止并移除服务及其进程）
  AddLog('Cleaning up old service...');
  SilanesExec('--delete hydride_svc64', DummyErr);

  // 3. 强制终止残余的 hydride_svc64.exe 进程（含手动运行的实例）
  AddLog('Terminating leftover processes...');
  ExecAndCaptureOutput('taskkill.exe', '/F /IM hydride_svc64.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode, Output);

  // 4. 等待所有相关进程完全退出
  WaitForOldProcess;

  // 5. 若旧安装目录与本次目标目录不同，删除旧目录残留文件
  // （改目录更新时旧 exe/libs/卸载器会留在旧目录，此处统一清掉）
  if RegQueryStringValue(HKLM, UninstallKey, 'InstallLocation', OldDir) or
     RegQueryStringValue(HKLM, NSISUninstallKey, 'InstallLocation', OldDir) then
  begin
    if (OldDir <> '') and (Pos('Hydride', OldDir) > 0) and
       (CompareText(OldDir, ExpandConstant('{app}')) <> 0) then
    begin
      AddLog('Removing old install directory: ' + OldDir);
      DelTree(OldDir, True, True, True);
    end;
  end;

  AddLog('Cleanup done.');
end;

// ── 服务注册：文件复制完成后调用（ssPostInstall）──
procedure ConfigureService;
begin
  // 1. 写入服务 YAML（此时 {app}\libs 已复制就位）
  CreateServiceYaml;

  // 2. 注册服务（日志文本与 NSIS 版一致）
  AddLog('Registering Hydride service...');
  if not RunSilanesCommand(ExpandConstant('--install "{app}\libs\hydride_svc64.yaml"'), CustomMessage('RegisterFail')) then
    Exit;

  // 3. 启动服务
  AddLog('Starting Hydride service...');
  if not RunSilanesCommand('--start hydride_svc64', CustomMessage('StartFail')) then
    Exit;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    AddLog('Starting installation...')
  else if CurStep = ssPostInstall then
    ConfigureService
  else if CurStep = ssDone then
    AddLog('Installation complete.');
end;

// ── 卸载：Silanes 检查 + 删除服务 ──
// Inno 7 无 AbortInstall，通过 InitializeUninstall 返回 False 中止卸载
function InitializeUninstall: Boolean;
var
  SilanesPath: String;
begin
  Result := True;

  // 1. 前置检查：Silanes
  if not RegQueryStringValue(HKLM, SilanesKey, '', SilanesPath) then
  begin
    MsgBox(CustomMessage('SilanesNotFound'), mbError, MB_OK);
    Result := False;
    Exit;
  end;

  // 2. 删除服务：失败弹「终止 / 重试 / 忽略」
  if not RunSilanesCommand('--delete hydride_svc64', CustomMessage('DeleteFail')) then
    Result := False;
end;

// ── 完成页文档：按当前语言返回文档路径（中文界面 → 中文文档） ──
function GetDocPath(Param: String): String;
begin
  if ActiveLanguage = 'chinesesimp' then
    Result := ExpandConstant('{app}\docs\README_CN.html')
  else
    Result := ExpandConstant('{app}\docs\README_EN.html');
end;
