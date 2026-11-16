import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyApm27kmQkjh9rcFoEFz3Ned3IG2bbOgn8',
      appId: '1:330541466611:web:7ff1d3f1d538f99c52c886',
      messagingSenderId: '330541466611',
      projectId: 'she-m-8d0f5',
      authDomain: 'she-m-8d0f5.firebaseapp.com',
      databaseURL:
          'https://she-m-8d0f5-default-rtdb.asia-southeast1.firebasedatabase.app',
      storageBucket: 'she-m-8d0f5.firebasestorage.app',
    );
  }
}
