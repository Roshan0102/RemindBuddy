# SSH Setup for GitHub Actions Deployment

This guide will help you generate an SSH key pair so GitHub Actions can connect to your new GCP server and deploy the code.

## 1. Generate a New SSH Key Pair (On Your Local Machine)

Run this command in your local terminal (NOT on the server):

```bash
ssh-keygen -t rsa -b 4096 -C "github-actions-deploy" -f ~/.ssh/gcp_deploy_key -N ""
```

*   This creates two files in `~/.ssh/`:
    *   `gcp_deploy_key` (Private Key - Goes to GitHub Secrets)
    *   `gcp_deploy_key.pub` (Public Key - Goes to the Server)

## 2. Add Public Key to the Server

1.  **Copy the Public Key**:
    Run this command locally to see the key:
    ```bash
    cat ~/.ssh/gcp_deploy_key.pub
    ```
    *Copy the entire output (starts with `ssh-rsa` and ends with `github-actions-deploy`).*

2.  **Paste into Server**:
    *   Go to your **Server Terminal** (where you are connected via SSH).
    *   Run this command to open the authorized keys file:
        ```bash
        nano ~/.ssh/authorized_keys
        ```
    *   Scroll to the bottom (use arrow keys).
    *   **Paste** the key you copied (Ctrl+Shift+V or Right Click > Paste).
    *   **Save and Exit**: Press `Ctrl+O`, `Enter`, then `Ctrl+X`.

## 3. Update GitHub Secrets

1.  Go to your GitHub Repository > **Settings** > **Secrets and variables** > **Actions**.
2.  Update the following secrets:

    *   **`SERVER_HOST`**: `35.237.49.45`
    *   **`SERVER_USERNAME`**: `roshanjustinjr2002` (or whatever your username is on the server)
    *   **`SERVER_SSH_KEY`**:
        *   Run this locally to get the private key:
            ```bash
            cat ~/.ssh/gcp_deploy_key
            ```
        *   Copy the **ENTIRE** content (including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`).
        *   Paste this into the secret value.

## 4. Verify Connection (Optional)

You can test if the key works by trying to connect from your local machine using the key:

```bash
ssh -i ~/.ssh/gcp_deploy_key roshanjustinjr2002@35.237.49.45
```

If you log in without a password, it works!
