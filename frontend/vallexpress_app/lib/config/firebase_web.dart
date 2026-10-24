import 'package:firebase_core/firebase_core.dart';

/// Configuración de la app web "ValleXpress Web" en Firebase (proyecto vallexpress-delivery). No es secreta:
/// va dentro de la página pública. Debe coincidir con web/firebase-messaging-sw.js.
const firebaseWeb = FirebaseOptions(
  apiKey: 'AIzaSyCwRpcJOLsN6v7ZjxBLJKcD5Ze6UMHbjHI',
  appId: '1:209736935156:web:6bdf4c74ec989da73720a1',
  messagingSenderId: '209736935156',
  projectId: 'vallexpress-delivery',
  authDomain: 'vallexpress-delivery.firebaseapp.com',
  storageBucket: 'vallexpress-delivery.firebasestorage.app',
);
