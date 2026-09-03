# Task Scheduler Setup - Python版 SSH Auto Reconnect

Python版`ssh_reconnect.py`をタスクスケジューラーで実行するための設定手順です。

## 前提条件

1. Pythonがインストールされていること
2. 依存関係がインストールされていること: `pip install -r .\auto_ssh\requirements.txt`
3. `config.py`が作成・設定されていること
4. Playwrightブラウザがインストールされていること: `python -m playwright install chromium`

## Python実行ファイルのパス確認

まず、使用するPython実行ファイルのパスを確認してください:

```powershell
# PowerShellでは `where` ではなく `Get-Command` を使用
Get-Command python

# またはWindowsのwhere.exeを明示
where.exe python

# このワークスペースの仮想環境
Test-Path "$env:USERPROFILE\automation_on_windows\.venv\Scripts\python.exe"
& "$env:USERPROFILE\automation_on_windows\.venv\Scripts\python.exe" --version
```

## タスクスケジューラー設定手順

### 方法1: GUIで手動設定（推奨）

#### 1. タスクスケジューラーを開く

- `Win + R`を押して、`taskschd.msc`と入力してEnter

#### 2. 新しいタスクを作成

- 右側の「**タスクの作成**」をクリック（「基本タスクの作成」ではない）

#### 3. 全般タブの設定

- **名前**: `SSH-RDP_auto-connect-Python`
- **場所**: `\User\`（タスクスケジューラの「User」フォルダ）
- **説明**: `Automatically maintain SSH connection via Cloudflare Access (Python version)`
- **セキュリティオプション**:
  - ✅ **ユーザーがログオンしているときのみ実行する**（重要！GUIアプリケーションを表示するため）
  - **ユーザーまたはグループ**: `%USERNAME%`（現在のユーザー名）
  - ✅ **最上位の特権で実行する**（チェックしない）

#### 4. トリガータブの設定

**トリガー1: ログオン時**

- 「**新規**」をクリック
- **タスクの開始**: 「**ログオン時**」を選択
- **特定のユーザー**: `%USERNAME%`（現在のユーザー名）
- 「**OK**」をクリック

**トリガー2: イベント時（既存のネットワーク監視システムを使用する場合）**

- 「**新規**」をクリック
- **タスクの開始**: 「**イベント時**」を選択
- **カスタムイベントフィルター**を選択
- 「**イベントフィルターの編集**」をクリック
- **XML**タブに切り替え
- ✅ **クエリを手動で編集する**にチェック
- 以下のXMLを貼り付け:

```xml
<QueryList>
  <Query Id="0">
    <Select Path="Application">
      *[System[Provider[@Name='NetworkMonitor'] and EventID=1002]]
    </Select>
  </Query>
</QueryList>
```

- 「**OK**」をクリック

**注意**: ネットワーク監視システムを使用しない場合は、トリガー1のみで十分です。

#### 5. 操作タブの設定（重要）

- 「**新規**」をクリック
- **操作**: 「**プログラムの開始**」を選択
- **プログラム/スクリプト**: Python実行ファイルの**フルパス**を入力
  - **重要**: コンソールウィンドウを非表示にするため、`pythonw.exe`を使用してください
  - 例: `C:\Python39\pythonw.exe`（`python.exe`ではなく`pythonw.exe`）
  - このワークスペース: `C:\Users\[your_username]\automation_on_windows\.venv\Scripts\pythonw.exe`
- **引数の追加**: `ssh_reconnect.py`の**フルパス**を入力
  - 例: `"C:\Users\[your_username]\automation_on_windows\auto_ssh\ssh_reconnect.py"`
  - **重要**: パスにスペースが含まれる場合は、ダブルクォートで囲む
- **開始場所（オプション）**: `ssh_reconnect.py`があるディレクトリの**フルパス**
  - 例: `C:\Users\[your_username]\automation_on_windows\auto_ssh`
- 「**OK**」をクリック

**注意**: 操作タブはPowerShellではないため、`$env:USERPROFILE`や`$env:USERNAME`は展開されません。GUIには実際のユーザープロファイルパスを入力してください。`$env:USERPROFILE`が使えるのは、下記のPowerShellコードをPowerShellで実行する場合です。

**設定例**:
```
プログラム/スクリプト: C:\Python39\pythonw.exe  （python.exeではなくpythonw.exe）
引数の追加: "C:\Users\[your_username]\automation_on_windows\auto_ssh\ssh_reconnect.py"
開始場所: C:\Users\[your_username]\automation_on_windows\auto_ssh
```

**注意**: `pythonw.exe`を使用することで、コンソールウィンドウが表示されません。

#### 6. 条件タブの設定

- ❌ **コンピューターがAC電源に接続されている場合のみタスクを開始する**（チェックを外す）
- ❌ **バッテリーモードに切り替えた場合、タスクを停止する**（チェックを外す）
- ✅ **タスクを開始するためにコンピューターをスリープ解除する**（チェックを入れる）

#### 7. 設定タブの設定

- ✅ **要求時に実行できるようにする**
- ✅ **スケジュールされた時刻にタスクの開始に失敗した場合、できるだけ早く実行する**
- ✅ **タスクが失敗した場合、再起動する間隔**: `1分`（オプション）
- **タスクが次の時間を超えて実行されている場合は停止する**: `1日`（または無制限）
- ✅ **タスクが要求されたときに実行中の場合、新しいインスタンスを並行して実行する**（チェックを外す - 重要！）

#### 8. 保存

- 「**OK**」をクリック
- パスワードの入力を求められた場合は、現在のユーザーのパスワードを入力

### 方法2: PowerShellで自動設定

管理者としてPowerShellを開き、`register_task_python.ps1`を実行すると、タスクスケジューラーの `User` フォルダに自動登録されます。スクリプトは、このファイル自身の場所からワークスペースと `.venv` を解決し、`NetworkMonitor` の Event ID `1002` でも起動するように設定します。

```powershell
Set-Location "$env:USERPROFILE\automation_on_windows"
powershell -ExecutionPolicy Bypass -File ".\auto_ssh\register_task_python.ps1"
```

既存の同名タスクがある場合は、登録前に削除して再登録します。`User` フォルダのタスクを更新するため、必ず管理者としてPowerShellを実行してください。

## テスト方法

### 1. 手動でタスクを実行

1. タスクスケジューラーの `User` フォルダで `SSH-RDP_auto-connect-Python` タスクを右クリック
2. 「**実行**」を選択
3. ブラウザウィンドウが表示されることを確認（Cloudflare認証が必要な場合）

### 2. ログを確認

```powershell
# 今日のログファイルを確認
$logFile = "$env:USERPROFILE\automation_on_windows\auto_ssh\logs\ssh_reconnect_$(Get-Date -Format 'yyyyMMdd').log"
Get-Content $logFile -Tail 50

# リアルタイムで監視
Get-Content $logFile -Wait -Tail 20
```

### 3. SSH接続を確認

```powershell
# ポート3956がリッスンしているか確認
Get-NetTCPConnection -LocalPort 3956 -State Listen

# SSHプロセスを確認
Get-Process -Name ssh -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*your_ssh_host*"
}
```

## トラブルシューティング

### ブラウザが表示されない

1. **「ユーザーがログオンしているときのみ実行する」が選択されているか確認**
   - これが最も重要です。GUIアプリケーションを表示するには必須です。

2. **タスクスケジューラーの「履歴」タブでエラーを確認**
   - タスクを右クリック → 「履歴の表示」でエラーメッセージを確認

3. **Pythonスクリプトを直接実行してテスト**
   ```powershell
   python "C:\Users\masahiro.sakamoto\automation_on_windows\auto_ssh\ssh_reconnect.py"
   ```
   これでブラウザが表示されれば、スクリプト自体は正常です。

### モジュールが見つからないエラー

- タスクスケジューラーで実行するPython環境に依存関係がインストールされているか確認
- 仮想環境を使用している場合は、仮想環境のPython実行ファイルを指定する

### SSH接続が確立されない

- `config.py`の設定を確認
- ログファイルでエラーメッセージを確認
- `~/.ssh/config`にホストが定義されているか確認

### タスクが自動実行されない

- トリガーが正しく設定されているか確認
- タスクスケジューラーの「履歴」タブで実行履歴を確認
- 「設定」タブで「スケジュールされた時刻にタスクの開始に失敗した場合、できるだけ早く実行する」が有効か確認

## 既存のPowerShell版タスクとの併用

**重要**: PowerShell版とPython版は同時に実行しないでください。

既存のPowerShell版タスクを無効化または削除してください:

```powershell
# PowerShell版タスクを無効化
Disable-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect"

# または削除
Unregister-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect" -Confirm:$false
```

## タスク管理コマンド

```powershell
# タスクの開始
Start-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect-Python"

# タスクの停止
Stop-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect-Python"

# タスクの状態確認
Get-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect-Python" | Select-Object TaskName, TaskPath, State, LastRunTime, NextRunTime

# タスクの無効化
Disable-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect-Python"

# タスクの有効化
Enable-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect-Python"

# タスクの削除
Unregister-ScheduledTask -TaskPath "\User\" -TaskName "SSH-RDP_auto-connect-Python" -Confirm:$false
```

## 重要な設定ポイントまとめ

1. ✅ **「ユーザーがログオンしているときのみ実行する」を選択**（GUI表示に必須）
2. ✅ **Python実行ファイルのフルパスを指定**
3. ✅ **スクリプトのフルパスを引数として指定**（スペースがある場合はダブルクォート）
4. ✅ **開始場所をスクリプトのディレクトリに設定**
5. ✅ **「新しいインスタンスを並行して実行する」を無効化**（重複実行を防ぐ）

これらの設定により、タスクスケジューラーから実行してもブラウザウィンドウが確実に表示されます。
