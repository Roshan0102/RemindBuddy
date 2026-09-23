// Give the service worker access to Firebase Messaging.
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker by passing the options.
firebase.initializeApp({
  apiKey: "AIzaSyCbEjEIltmuR_SNUqJTbvzeiqm_XotIk0s",
  authDomain: "remindbuddy-b68f9.firebaseapp.com",
  projectId: "remindbuddy-b68f9",
  storageBucket: "remindbuddy-b68f9.firebasestorage.app",
  messagingSenderId: "668661278882",
  appId: "1:668661278882:web:8a30741a2cc173fcb30ffb",
  measurementId: "G-V12R3CLTW1"
});

// Retrieve an instance of Firebase Messaging so that it can handle background messages.
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[RemindBuddy] Received background push message:', payload);
  const title = (payload.notification && payload.notification.title) || 
                (payload.data && payload.data.title) || 
                "RemindBuddy Alert";
  const body = (payload.notification && payload.notification.body) || 
               (payload.data && payload.data.body) || 
               "You have a new update in RemindBuddy.";
  const tag = (payload.data && payload.data.tag) || `remindbuddy_${Date.now()}`;

  const notificationOptions = {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: tag,
    data: Object.assign({}, payload.data || {}, {
      fcmOptions: payload.fcmOptions || {},
      notification: payload.notification || {}
    })
  };

  self.registration.showNotification(title, notificationOptions);
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const notifData = (event.notification && event.notification.data) || {};
  const featureType = notifData.type || notifData.feature || notifData.click_action || '';
  
  let targetUrl = '/';
  if (notifData.fcmOptions && notifData.fcmOptions.link) {
    targetUrl = notifData.fcmOptions.link;
  } else if (featureType) {
    targetUrl = '/?feature=' + encodeURIComponent(featureType);
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (let i = 0; i < clientList.length; i++) {
        let client = clientList[i];
        if (client.url && 'focus' in client) {
          client.focus();
          if (featureType) {
            client.postMessage({
              action: 'NAVIGATE_FEATURE',
              feature: featureType,
              type: featureType,
              data: notifData
            });
          }
          return;
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
