# RemindBuddy Deployment Guide

## 1. Prerequisites (Oracle Free Tier VM)
- OS: Ubuntu 20.04 or 22.04 (Recommended)
- Tools: Node.js, Nginx, PM2, Git

### Install Node.js & Nginx
```bash
sudo apt update
sudo apt install -y nginx git curl
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pm2
```

## 2. Backend Deployment
1. **Upload Code**: Copy the `backend` folder to the server (e.g., `/var/www/remindbuddy/backend`).
2. **Install Dependencies**:
   ```bash
   cd /var/www/remindbuddy/backend
   npm install
   ```
3. **Start with PM2**:
   ```bash
   pm2 start server.js --name remindbuddy-api
   pm2 save
   pm2 startup
   ```

## 3. Frontend Deployment (Flutter Web)
1. **Build Web**:
   Run this on your local machine:
   ```bash
   cd frontend
   flutter build web --release
   ```
   The output will be in `build/web`.

2. **Upload Web Build**:
   Copy the contents of `build/web` to `/var/www/remindbuddy/frontend`.

## 4. Android APK Build
To build the Android APK for distribution:
```bash
cd frontend
flutter build apk --release
```
The APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.

## 5. Nginx Reverse Proxy Configuration
Configure Nginx to serve the Flutter Web app and proxy API requests to Node.js.

1. **Edit Config**:
   ```bash
   sudo nano /etc/nginx/sites-available/default
   ```

2. **Configuration**:
   Replace the content with:
   ```nginx
   server {
       listen 80;
       server_name your_domain_or_ip;

       root /var/www/remindbuddy/frontend;
       index index.html;

       # Serve Flutter Web
       location / {
           try_files $uri $uri/ /index.html;
       }

       # Proxy API requests to Node.js
       location /api {
           proxy_pass http://localhost:3000;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection 'upgrade';
           proxy_set_header Host $host;
           proxy_cache_bypass $http_upgrade;
       }
   }
   ```

3. **Restart Nginx**:
   ```bash
   sudo systemctl restart nginx
   ```

## 6. Database Integration (Future)
- **SQLite**: The current backend uses an in-memory array. To use SQLite, install `sqlite3` and update `models/taskModel.js`.
- **MongoDB**: Install MongoDB on the VM or use Atlas. Update `models/taskModel.js` to use Mongoose.

## 7. Sync Logic Notes
- The app syncs on startup and periodically (every hour) while open.
- For background sync when the app is closed, you must implement `workmanager` or `background_fetch` in Flutter.
