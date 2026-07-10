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
  console.log('Received background message ', payload);
  // Customize notification here
  const notificationTitle = payload.notification.title || "RemindBuddy Alert";
  const notificationOptions = {
    body: payload.notification.body || "",
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
