import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream to listen to auth state changes
  Stream<User?> get userStream => _auth.authStateChanges();

  // 1. Email & Password Sign Up
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // 2. Email & Password Sign In
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // 3. Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    // Initialize GoogleSignIn (Required in v7.0.0+)
    await GoogleSignIn.instance.initialize();

    // Trigger the authentication flow (Replacing signIn() in v7.0.0+)
    final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();

    // Obtain the auth details (Sync getter in v7.0.0+, no 'await' needed)
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    // Create a new credential using only idToken (accessToken is removed in v7.0.0+)
    final AuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    // Once signed in, return the UserCredential
    return await _auth.signInWithCredential(credential);
  }

  // Sign Out
  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
