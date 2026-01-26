# SSH Auto Reconnect Script (Python版)

PowerShellからPythonスクリプトを呼び出してもブラウザウィンドウが表示されない問題を解決するため、`ssh_reconnect.ps1`の機能をPythonスクリプトに移植しました。

## 主な改善点

1. **ブラウザ表示の問題を解決**: Pythonスクリプトから直接ブラウザを起動するため、PowerShellのバックグラウンドジョブの制約を受けません
2. **統合されたCloudflare認証**: `cloudflare_approve.py`の機能を直接呼び出すため、ブラウザウィンドウが確実に表示されます
3. **クロスプラットフォーム対応**: Windows以外でも動作する可能性があります（ただし、現在はWindows向けに最適化されています）

## セットアップ

### 1. 依存関係のインストール

```powershell
pip install -r requirements.txt
```

必要なライブラリ:
- `playwright`: ブラウザ自動化
- `psutil`: プロセス管理
- `win10toast`: Windows通知

### 2. 設定ファイルの作成

`config.py.example`を`config.py`にコピーして設定を編集してください:

```powershell
Copy-Item config.py.example config.py
```

`config.py`を編集して、以下の設定を変更してください:

```python
SSH_HOST = "your_ssh_host"  # ~/.ssh/configで定義されたホスト名
CHECK_INTERVAL = 30  # 接続チェック間隔（秒）
RECONNECT_DELAY = 5  # 再接続前の待機時間（秒）
MAX_RETRIES = 3  # 最大リトライ回数
LOG_DIR = "..."  # ログディレクトリのパス
```

### 3. Playwrightブラウザのインストール

初回実行時にPlaywrightのブラウザをインストールする必要があります:

```powershell
playwright install chromium
```

## 使用方法

### 直接実行

```powershell
python ssh_reconnect.py
```

### タスクスケジューラーでの実行

**詳細な設定手順は `TaskScheduler-Setup-Python.md` を参照してください。**

#### 簡単な方法: PowerShellスクリプトで自動登録

```powershell
# 管理者権限で実行（推奨）
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\automation_on_windows\auto_ssh\register_task_python.ps1"
```

#### 手動設定の要点

タスクスケジューラーで実行する場合、以下の設定が重要です:

1. **「ユーザーがログオンしているときのみ実行する」を選択**（GUI表示に必須）
2. **プログラム**: `pythonw.exe`のフルパス（例: `C:\Python39\pythonw.exe`）
   - **重要**: コンソールウィンドウを非表示にするため、`pythonw.exe`を使用してください（`python.exe`ではなく）
3. **引数**: `ssh_reconnect.py`のフルパス（例: `"C:\Users\username\automation_on_windows\auto_ssh\ssh_reconnect.py"`）
4. **開始場所**: `ssh_reconnect.py`があるディレクトリ
5. **実行時のユーザー**: 現在のユーザー（GUIアプリケーションを表示するため）

**重要**: 「ユーザーがログオンしているときのみ実行する」を選択しないと、ブラウザウィンドウが表示されません。

## PowerShell版との違い

### 利点

1. **ブラウザ表示の問題が解決**: Pythonから直接ブラウザを起動するため、確実にウィンドウが表示されます
2. **シンプルな実装**: PowerShellの複雑なバックグラウンドジョブやプロセス管理が不要
3. **統合された認証**: Cloudflare認証がメインスクリプトに統合されています

### 注意点

1. **設定ファイル形式**: PowerShell版は`config.ps1`、Python版は`config.py`を使用します
2. **依存関係**: Python版は追加のライブラリ（`psutil`、`win10toast`）が必要です
3. **Windows通知**: `win10toast`がインストールされていない場合、通知は無効になります（ログには記録されます）

## トラブルシューティング

### ブラウザが表示されない

- Pythonスクリプトを直接実行していることを確認してください（PowerShellから呼び出すのではなく）
- タスクスケジューラーで実行する場合、「ユーザーがログオンしているときのみ実行」を選択してください

### モジュールが見つからないエラー

```powershell
pip install -r requirements.txt
```

### SSH接続が確立されない

- `config.py`の`SSH_HOST`が正しく設定されているか確認してください
- `~/.ssh/config`にホストが定義されているか確認してください
- ログファイルを確認してエラーメッセージを確認してください

## ログファイル

ログファイルは`LOG_DIR`で指定されたディレクトリに保存されます（デフォルト: `%USERPROFILE%\automation_on_windows\auto_ssh\logs\`）。

ログファイル名: `ssh_reconnect_YYYYMMDD.log`

## 既存のPowerShell版との併用

Python版とPowerShell版は同時に実行しないでください。どちらか一方のみを実行してください。

PowerShell版からPython版に移行する場合:

1. PowerShell版のタスクスケジューラー設定を無効化または削除
2. Python版の設定ファイル（`config.py`）を作成
3. Python版を実行またはタスクスケジューラーに登録
