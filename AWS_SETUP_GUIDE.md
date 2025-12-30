# AWS EC2 Setup Guide for RemindBuddy

## Phase 1: Create an AWS Account
1.  **Sign Up**: Visit [aws.amazon.com](https://aws.amazon.com/) and create a free account.
2.  **Verification**: You will need a credit/debit card. AWS offers a "Free Tier" for 12 months which includes 750 hours/month of EC2 usage.

## Phase 2: Launch Your Virtual Machine (EC2 Instance)
1.  **Login** to the AWS Console.
2.  **Select Region**: Top right corner. Choose a region close to you (e.g., `us-east-1` N. Virginia, `ap-south-1` Mumbai).
3.  **Go to EC2**: Search for "EC2" in the top search bar and click it.
4.  **Launch Instance**: Click the orange **"Launch instance"** button.
5.  **Name**: Enter `RemindBuddyServer`.
6.  **OS Images (AMI)**:
    *   Select **Ubuntu**.
    *   Ensure it says **"Free tier eligible"** (usually Ubuntu Server 24.04 LTS or 22.04 LTS).
7.  **Instance Type**:
    *   Select **t2.micro** or **t3.micro** (Both are usually Free Tier eligible).
8.  **Key Pair (Login)**:
    *   Click **"Create new key pair"**.
    *   Name: `remindbuddy-key`.
    *   Type: `RSA`.
    *   Format: `.pem` (for Mac/Linux) or `.ppk` (for Windows PuTTY, though `.pem` is better for GitHub Actions). **Recommendation: Choose .pem**.
    *   Click **"Create key pair"**. It will download a file. **KEEP THIS SAFE.**
9.  **Network Settings**:
    *   Check **"Allow SSH traffic from"** -> Anywhere (0.0.0.0/0).
    *   Check **"Allow HTTP traffic from the internet"**.
    *   Check **"Allow HTTPS traffic from the internet"**.
10. **Launch**: Click **"Launch instance"**.

## Phase 3: Connect GitHub to AWS
You need to provide GitHub with the credentials to access your new AWS server.

### 1. Gather Information
*   **IP Address**: Go to your EC2 Dashboard -> Instances. Click your instance. Copy the **"Public IPv4 address"**.
*   **Username**: Default for Ubuntu is `ubuntu`.
*   **SSH Key**: Open the `.pem` file you downloaded in Phase 2 with a text editor (Notepad, TextEdit, VS Code) and copy the **entire** text (including `-----BEGIN RSA PRIVATE KEY-----`).

### 2. Add to GitHub
1.  Go to your GitHub Repo: [RemindBuddy](https://github.com/Roshan0102/RemindBuddy).
2.  Click **Settings** (top right tab).
3.  On the left sidebar, click **Secrets and variables** -> **Actions**.
4.  Click **"New repository secret"** (Green button).
5.  Add these 3 secrets:

| Name | Secret |
| :--- | :--- |
| `SERVER_HOST` | Paste your AWS **Public IPv4 Address** here. |
| `SERVER_USERNAME` | Type `ubuntu`. |
| `SERVER_SSH_KEY` | Paste the **entire content** of your `.pem` file here. |

## Phase 4: First-Time Server Setup
You need to log in once to install the necessary software.

1.  **Connect via Terminal** (Mac/Linux/Windows PowerShell):
    ```bash
    # 1. Go to folder where you downloaded the key
    cd ~/Downloads

    # 2. Change permission (Critical step!)
    chmod 400 remindbuddy-key.pem

    # 3. Connect
    ssh -i remindbuddy-key.pem ubuntu@<YOUR_AWS_PUBLIC_IP>
    ```

2.  **Run Setup Commands**:
    Copy and paste this block into your server terminal:
    ```bash
    # Install Node.js, Nginx, Git, PM2
    sudo apt update
    sudo apt install -y nginx git curl
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
    sudo npm install -g pm2

    # Clone App
    sudo mkdir -p /var/www/remindbuddy
    sudo chown -R $USER:$USER /var/www/remindbuddy
    git clone https://github.com/Roshan0102/RemindBuddy.git /var/www/remindbuddy

    # Start Backend
    cd /var/www/remindbuddy/backend
    npm install
    pm2 start server.js --name remindbuddy-api
    pm2 save
    pm2 startup

    # Configure Nginx
    sudo bash -c 'cat > /etc/nginx/sites-available/default <<EOF
    server {
        listen 80;
        server_name _;

        location /api {
            proxy_pass http://localhost:3000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
        }
    }
    EOF'

    # Restart Nginx
    sudo systemctl restart nginx
    ```

## Phase 5: Done!
Your server is now running.
- **App Updates**: Whenever you push code to GitHub, the "Deploy" action will automatically update this server using the secrets you provided.
