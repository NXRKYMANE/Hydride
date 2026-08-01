; Hydride 安装脚本
; --------------------------------------------

!define PRODUCT_NAME "Hydride"
!define PRODUCT_VERSION "1.0.0"
!define PRODUCT_PUBLISHER "Copyright (c) 2026 NXRKYMANE SOFTWARE"
!define PRODUCT_WEB_SITE "https://github.com/NXRKYMANE/Hydride"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\hydride_svc64.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

SetCompressor lzma

; 需要管理员权限
RequestExecutionLevel admin

; --- MUI 2.0 ---
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WordFunc.nsh"
!include "StrFunc.nsh"
${Using:StrFunc} StrStr
!insertmacro VersionCompare

!define MUI_ABORTWARNING
!define MUI_ICON "misc\ServiceIcon.ico"
!define MUI_UNICON "misc\ServiceIcon.ico"

; 向导位图 (164x314 BMP)
!define MUI_WELCOMEFINISHPAGE_BITMAP "misc\Background.bmp"

; 现代字体
!define MUI_FONT "Segoe UI"
!define MUI_FONTSIZE "9"

; 欢迎页
!insertmacro MUI_PAGE_WELCOME
; 目录选择页
!insertmacro MUI_PAGE_DIRECTORY
; 安装页
!insertmacro MUI_PAGE_INSTFILES
; 完成页：一个复选框，文字根据语言自适应
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "$(READMECHECK_TEXT)"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenDoc
!define MUI_FINISHPAGE_RUN_NOTCHECKED

!insertmacro MUI_PAGE_FINISH

Function OpenDoc
  ${If} $LANGUAGE == 2052
    ExecShell "" "$INSTDIR\docs\README_CN.html"
  ${Else}
    ExecShell "" "$INSTDIR\docs\README_EN.html"
  ${EndIf}
FunctionEnd

; 卸载页
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; 语言
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

LangString READMECHECK_TEXT ${LANG_ENGLISH} "View Documentation"
LangString READMECHECK_TEXT ${LANG_SIMPCHINESE} "查看中文文档"

; --- 语言选择 ---
!define MUI_LANGDLL_REGISTRY_ROOT "HKLM"
!define MUI_LANGDLL_REGISTRY_KEY "${PRODUCT_UNINST_KEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Installer Language"

Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY

  ; 检测旧版本安装
  ReadRegStr $0 HKLM "${PRODUCT_UNINST_KEY}" "UninstallString"
  ${If} $0 != ""
    ; 版本比较：升级时不弹确认框
    ReadRegStr $R1 HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion"
    ${VersionCompare} "${PRODUCT_VERSION}" "$R1" $R2
    ${If} $R2 == 1
      ; 新版本：静默升级
      Goto uninstall_old
    ${ElseIf} $R2 == 2
      ; 旧版本：降级警告（本地化）
      ${If} $LANGUAGE == 2052
        StrCpy $R9 "已安装更新的版本 (v$R1)。$\n$\n降级到 v${PRODUCT_VERSION}？"
      ${Else}
        StrCpy $R9 "A newer version (v$R1) is already installed.$\n$\nDowngrade to v${PRODUCT_VERSION}?"
      ${EndIf}
      MessageBox MB_YESNO $R9 /SD IDNO IDYES uninstall_old
      Quit
    ${EndIf}

    ${If} $LANGUAGE == 2052
      StrCpy $R9 "已安装相同版本的 Hydride (v$R1)。$\n$\n是否重新安装？"
    ${Else}
      StrCpy $R9 "An identical version (v$R1) is already installed.$\n$\nReinstall?"
    ${EndIf}
    MessageBox MB_YESNO $R9 /SD IDYES IDYES uninstall_old
    Quit
    uninstall_old:
    StrCpy $1 "$0" "" -4
    ${If} $1 != ".exe"
      StrCpy $0 "$0.exe"
    ${EndIf}
    ExecWait '"$0" /S _?=$INSTDIR'
  ${EndIf}

  ; 静默模式（/S）：等待旧服务进程完全退出
  ; （最长 30 秒），避免覆盖正在运行的 exe 失败。
  IfSilent do_wait skip_wait
  do_wait:
    StrCpy $R3 0
    wait_exit:
    nsExec::ExecToStack 'tasklist /FI "IMAGENAME eq hydride_svc64.exe" /FO CSV /NH'
    Pop $R2  ; 退出码（恒为 0，忽略）
    Pop $R4  ; 输出：运行中则含 "hydride_svc64.exe"
    ${StrStr} $R5 $R4 "hydride_svc64.exe"
    ${If} $R5 == ""
      Goto process_exited
    ${EndIf}
    IntOp $R3 $R3 + 1
    ${If} $R3 < 30
      Sleep 1000
      Goto wait_exit
    ${EndIf}
    process_exited:
  skip_wait:
FunctionEnd

; --- 配置 ---
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "publish\hydride-svc-win-x64-setup-v${PRODUCT_VERSION}.exe"
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}"
InstallDirRegKey HKLM "${PRODUCT_DIR_REGKEY}" ""
ShowInstDetails show
ShowUnInstDetails show
BrandingText "${PRODUCT_PUBLISHER}"

; --- 安装包 exe 的版本元数据 ---
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName"     "Hydride System Memory Manager Service"
VIAddVersionKey "ProductVersion"  "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName"     "NXRKYMANE SOFTWARE"
VIAddVersionKey "LegalCopyright"  "${PRODUCT_PUBLISHER}"
VIAddVersionKey "FileVersion"     "${PRODUCT_VERSION}"
VIAddVersionKey "FileDescription" "Hydride Installer"

; --- 安装 ---
Section "Install"
  SetOutPath "$INSTDIR"

  File "publish\hydride_svc64.exe"
  File "/oname=icon.ico" "misc\ServiceIcon.ico"
  File /r "docs"
  File /r "libs"

  ; 写入包含正确安装路径的 YAML 配置
  ; 只写必填字段：可选字段使用 Silanes 默认值
  FileOpen $0 "$INSTDIR\libs\hydride_svc64.yaml" w
  FileWrite $0 'service_name: hydride_svc64$\r$\n'
  FileWrite $0 'service_display_name: Hydride System Memory Manager Service$\r$\n'
  FileWrite $0 'service_description: Automatically manages system memory usage$\r$\n'
  FileWrite $0 'service_executable_path: $INSTDIR\hydride_svc64.exe$\r$\n'
  FileClose $0

  ; 删除 NSIS 路径保留产生的多余 "publish" 目录
  RMDir /r "$INSTDIR\publish"

  ; 从注册表查找 Silanes 路径
  ReadRegStr $2 HKLM "Software\Microsoft\Windows\CurrentVersion\App Paths\silanes64.exe" ""
  ${If} $2 == ""
    ${If} $LANGUAGE == 2052
      MessageBox MB_ICONSTOP "未找到 Silanes。$\n请先安装 Silanes: https://github.com/NXRKYMANE/Silanes 再安装 Hydride。"
    ${Else}
      MessageBox MB_ICONSTOP "Silanes is required but not found.$\nPlease install Silanes from https://github.com/NXRKYMANE/Silanes before installing Hydride."
    ${EndIf}
    Abort
  ${EndIf}

  ; 注册服务
  DetailPrint "Registering Hydride service..."
  try_install:
  nsExec::ExecToStack '"$2" -m --install "$INSTDIR\libs\hydride_svc64.yaml"'
  Pop $0  ; 退出码
  Pop $1  ; stderr/stdout 输出
  ${If} $0 != 0
    ${If} $LANGUAGE == 2052
      MessageBox MB_ABORTRETRYIGNORE|MB_ICONEXCLAMATION "注册服务失败。$\r$\n$\r$\n$1$\r$\n$\r$\n「终止」退出安装  「重试」重新注册  「忽略」跳过并继续" /SD IDIGNORE IDRETRY try_install IDIGNORE skip_install
    ${Else}
      MessageBox MB_ABORTRETRYIGNORE|MB_ICONEXCLAMATION "Failed to register service.$\r$\n$\r$\n$1$\r$\n$\r$\nAbort: exit setup  |  Retry: try again  |  Ignore: skip and continue" /SD IDIGNORE IDRETRY try_install IDIGNORE skip_install
    ${EndIf}
    Abort
  ${EndIf}
  skip_install:

  ; 启动服务
  DetailPrint "Starting Hydride service..."
  try_start:
  nsExec::ExecToStack '"$2" -m --start hydride_svc64'
  Pop $0  ; 退出码
  Pop $1  ; stderr/stdout 输出
  ${If} $0 != 0
    ${If} $LANGUAGE == 2052
      MessageBox MB_ABORTRETRYIGNORE|MB_ICONEXCLAMATION "启动服务失败。$\r$\n$\r$\n$1$\r$\n$\r$\n「终止」退出安装  「重试」重新启动  「忽略」跳过并继续" /SD IDIGNORE IDRETRY try_start IDIGNORE skip_start
    ${Else}
      MessageBox MB_ABORTRETRYIGNORE|MB_ICONEXCLAMATION "Failed to start service.$\r$\n$\r$\n$1$\r$\n$\r$\nAbort: exit setup  |  Retry: try again  |  Ignore: skip and continue" /SD IDIGNORE IDRETRY try_start IDIGNORE skip_start
    ${EndIf}
    Abort
  ${EndIf}
  skip_start:

  ; 卸载相关的注册表项
  WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\hydride_svc64.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "Hydride System Memory Manager Service"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninst.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\hydride_svc64.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Installer Language" $LANGUAGE

  ; 快捷方式
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Hydride.lnk" "$INSTDIR\hydride_svc64.exe"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk" "$INSTDIR\uninst.exe"

  WriteUninstaller "$INSTDIR\uninst.exe"
SectionEnd

; --- 卸载 ---
Section "Uninstall"
  ; 删除服务
  DetailPrint "Removing Hydride service..."
  ReadRegStr $2 HKLM "Software\Microsoft\Windows\CurrentVersion\App Paths\silanes64.exe" ""
  ${If} $2 == ""
    ${If} $LANGUAGE == 2052
      MessageBox MB_ICONSTOP "未找到 Silanes。$\n请重新安装 Silanes: https://github.com/NXRKYMANE/Silanes 后再卸载 Hydride。"
    ${Else}
      MessageBox MB_ICONSTOP "Silanes is required for uninstall but not found.$\nPlease reinstall Silanes from https://github.com/NXRKYMANE/Silanes before uninstalling Hydride."
    ${EndIf}
    Abort
  ${EndIf}

  try_delete:
  nsExec::ExecToStack '"$2" -m --delete hydride_svc64'
  Pop $0  ; 退出码
  Pop $1  ; stderr/stdout 输出
  ${If} $0 != 0
    ${If} $LANGUAGE == 2052
      MessageBox MB_ABORTRETRYIGNORE|MB_ICONEXCLAMATION "删除服务失败。$\r$\n$\r$\n$1$\r$\n$\r$\n「终止」退出卸载  「重试」重新尝试  「忽略」跳过并继续" /SD IDIGNORE IDRETRY try_delete IDIGNORE skip_delete
    ${Else}
      MessageBox MB_ABORTRETRYIGNORE|MB_ICONEXCLAMATION "Failed to delete service.$\r$\n$\r$\n$1$\r$\n$\r$\nAbort: exit uninstall  |  Retry: try again  |  Ignore: skip and continue" /SD IDIGNORE IDRETRY try_delete IDIGNORE skip_delete
    ${EndIf}
    Abort
  ${EndIf}
  skip_delete:

  ; 删除整个安装目录
  RMDir /r "$INSTDIR"

  ; 删除快捷方式
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\Hydride.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"

  DeleteRegKey HKLM "${PRODUCT_DIR_REGKEY}"
  DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
SectionEnd
