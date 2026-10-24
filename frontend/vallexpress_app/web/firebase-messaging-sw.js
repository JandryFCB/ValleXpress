// Recibe las notificaciones push de ValleXpress con la pestaña cerrada o en segundo plano (Firebase Cloud Messaging).
// Firebase las muestra solo; al tocarla abre el enlace que manda el backend (webpush.fcmOptions.link).
// La configuración debe coincidir con lib/config/firebase_web.dart.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCwRpcJOLsN6v7ZjxBLJKcD5Ze6UMHbjHI',
  appId: '1:209736935156:web:6bdf4c74ec989da73720a1',
  messagingSenderId: '209736935156',
  projectId: 'vallexpress-delivery',
  authDomain: 'vallexpress-delivery.firebaseapp.com',
  storageBucket: 'vallexpress-delivery.firebasestorage.app',
});

firebase.messaging();
