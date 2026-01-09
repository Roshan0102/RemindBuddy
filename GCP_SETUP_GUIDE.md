# Google Cloud Platform (GCP) "Always Free" VM Setup Guide

This guide will help you create a Virtual Machine on Google Cloud that stays within the "Always Free" tier limits, ensuring you don't get charged.

## 1. Create the VM Instance

1.  Go to the **[Google Cloud Console](https://console.cloud.google.com/)**.
2.  Navigate to **Compute Engine** > **VM instances**.
3.  Click **Create Instance**.
4.  **Name**: `remindbuddy-server` (or any name you like).
5.  **Region**: You **MUST** select one of the following to be free:
    *   `us-west1` (Oregon)
    *   `us-central1` (Iowa)
    *   `us-east1` (South Carolina)
6.  **Zone**: Any zone in the selected region (e.g., `us-central1-a`).
7.  **Machine Configuration**:
    *   **Series**: `E2`
    *   **Machine type**: `e2-micro` (2 vCPU, 1 GB memory).
    *   *Note: You might see a "Low usage" warning, ignore it. This is the free tier instance.*
8.  **Boot Disk**:
    *   Click **Change**.
    *   **Operating System**: `Ubuntu`
    *   **Version**: `Ubuntu 22.04 LTS` (x86/64).
    *   **Boot disk type**: `Standard persistent disk` (Do NOT choose SSD).
    *   **Size**: `30` GB (This is the max free limit).
    *   Click **Select**.
9.  **Firewall**:
    *   Check `Allow HTTP traffic`.
    *   Check `Allow HTTPS traffic`.
10. Click **Create**.

---

## 2. Reserve a Static IP Address (Optional but Recommended)
To prevent your server IP from changing every time you restart it:

1.  Go to **VPC network** > **IP addresses**.
2.  Click **Reserve External Static IP Address**.
3.  **Name**: `remindbuddy-ip`.
4.  **Region**: Same region as your VM (e.g., `us-central1`).
5.  **Attached to**: Select your `remindbuddy-server`.
6.  Click **Reserve**.

---

## 3. Connect to Your VM

### Option A: Browser SSH (Easiest)
1.  In the VM instances list, click the **SSH** button next to your instance.
2.  A new window will open with a terminal connected to your server.

### Option B: Local Terminal (Advanced)
1.  Install the **[Google Cloud CLI](https://cloud.google.com/sdk/docs/install)** on your computer.
2.  Run `gcloud init` to log in.
3.  Run the connect command (you can find this by clicking the arrow next to SSH > View gcloud command):
    ```bash
    gcloud compute ssh --zone "us-central1-a" "remindbuddy-server"  --project "your-project-id"
    ```

---

## 4. Crucial First Step: Set up Swap Memory
Since the `e2-micro` only has 1GB RAM, your server **will crash** if you try to run Node.js and a Database without Swap. Run these commands immediately after connecting:

```bash
# 1. Create a 2GB swap file
sudo fallocate -l 2G /swapfile

# 2. Set permissions
sudo chmod 600 /swapfile

# 3. Mark it as swap space
sudo mkswap /swapfile

# 4. Enable it
sudo swapon /swapfile

# 5. Make it permanent (so it stays after reboot)
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 6. Adjust "swappiness" (to use swap more often)
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
```

## 5. Install Software (Node.js, Nginx, SQLite)

Run these commands to set up your environment:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Nginx (Web Server)
sudo apt install nginx -y

# Install Node.js (v18)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2 (Process Manager to keep app running)
sudo npm install -g pm2

# Install Git
sudo apt install git -y
```

You are now ready to deploy your code!
