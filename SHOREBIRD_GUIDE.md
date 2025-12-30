# Shorebird OTA Setup Guide

## 1. Create a Shorebird Account
1.  Visit [console.shorebird.dev](https://console.shorebird.dev).
2.  Sign in with Google.

## 2. Initialize Shorebird (Local Machine)
You need to run these commands on your **local computer** (where you have the code), not on the server.

1.  **Install Shorebird CLI** (if you haven't):
    *   **Mac/Linux**: `curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh | bash`
    *   **Windows**: `powershell -Command "iwr -useb 'https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1' | iex"`

2.  **Login**:
    ```bash
    shorebird login
    ```
    (This will open your browser to authenticate).

3.  **Initialize Project**:
    Navigate to your project folder (`frontend` directory) and run:
    ```bash
    cd frontend
    shorebird init
    ```
    *   It will ask for your App Name (e.g., `RemindBuddy`).
    *   It will modify `pubspec.yaml` and create `shorebird.yaml`.

## 3. Get Your CI Token
To let GitHub Actions build your app, you need a token.
1.  Run this command in your terminal:
    ```bash
    shorebird login:ci
    ```
2.  Copy the token it prints (it looks like a long string of random characters).

## 4. Add Token to GitHub
1.  Go to your GitHub Repo -> **Settings** -> **Secrets and variables** -> **Actions**.
2.  Add a new secret:
    *   **Name**: `SHOREBIRD_TOKEN`
    *   **Value**: (Paste the token you copied).

## 5. How to Release & Update

### A. Create a New Release (APK)
When you change native code (Plugins, App Icon) or want a fresh start:
1.  Push your code to GitHub.
2.  The GitHub Action will run `shorebird release android`.
3.  Download the new APK from Artifacts and install it.

### B. Push an Update (OTA)
When you change **Flutter UI/Logic** only:
1.  Push your code to GitHub.
2.  **Manually Trigger the Patch Workflow** (I will create this for you).
    *   Go to Actions -> "Patch Update".
    *   Click "Run workflow".
3.  **Done!** Users will get the update automatically next time they open the app.
