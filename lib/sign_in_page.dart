import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/revenue_cat/paywall_page.dart';
import 'package:swim_analyzer/revenue_cat/purchases_service.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _isLoading = false;

  // --- STEP 3 LOGIC ---
  // This new, centralized method handles the post-login flow for any authentication method.
  Future<void> _handleSuccessfulLogin(User firebaseUser) async {
    try {
      // Fetch your custom AppUser object from Firestore (or your backend).
      final AppUser appUser = await _fetchAppUserDetails(firebaseUser.uid);

      // 1. Identify the user with RevenueCat. This links their device to their AppUser ID.
      await PurchasesService.identifyUser(appUser.id);

      // 2. Check if the user has any active subscriptions.
      final bool hasEntitlements =
          await PurchasesService.hasActiveEntitlements();

      if (!mounted) return;

      // 3. Navigate to the correct page based on entitlement status.
      if (hasEntitlements) {
        // User has an active subscription, go to the main app.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomePage(appUser: appUser)),
          (route) => false,
        );
      } else {
        // User has no active subscription, go to the paywall.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => PaywallPage(appUser: appUser)),
          (route) => false,
        );
      }
    } catch (e) {
      // If any part of the post-login flow fails, show an error.
      _showErrorSnackBar('Could not complete sign-in. Please try again.');
      setState(() => _isLoading = false);
    }
  }

  // Helper method to get your AppUser details from Firestore.
  // You might need to adjust this based on your actual data model.
  Future<AppUser> _fetchAppUserDetails(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) {
      throw Exception('User data not found in Firestore.');
    }
    return AppUser.fromJson(doc.id, doc.data()!);
  }

  // --- END OF STEP 3 LOGIC ---

  Future<void> _registerWithEmail() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // After successful registration, call the handler.
      if (userCredential.user != null) {
        // You'll need a step here to create the user document in Firestore first.
        // For simplicity, I'm assuming it exists. A real app would have a createUserDoc function.
        await _handleSuccessfulLogin(userCredential.user!);
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar('Registration failed: ${e.message}');
      setState(() => _isLoading = false);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithEmail() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // After successful sign-in, call the handler.
      if (userCredential.user != null) {
        await _handleSuccessfulLogin(userCredential.user!);
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar('Sign in failed: ${e.message}');
      setState(() => _isLoading = false);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName
        ],
        nonce: nonce,
      );

      final oAuthProvider = OAuthProvider('apple.com');
      final credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // After successful Apple sign-in, call the handler.
      if (userCredential.user != null) {
        await _handleSuccessfulLogin(userCredential.user!);
      }
    } catch (e, s) {
      debugPrint(e.toString());
      debugPrint(s.toString());
      _showErrorSnackBar('Sign in with Apple failed: $e');
      setState(() => _isLoading = false);
    }
  }

  String _generateNonce([int length = 32]) {
    final charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _emailController = kDebugMode
        ? TextEditingController(text: 'johannes.coach@gmail.com')
        : TextEditingController();
    _passwordController = kDebugMode
        ? TextEditingController(text: 'Test123456')
        : TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In'),
      ),
      body: IgnorePointer(
        ignoring: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Welcome to Swim Analyzer',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                        labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Please enter your email'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                        labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Please enter your password'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                                onPressed: _signInWithEmail,
                                child: const Text('Sign In')),
                            ElevatedButton(
                                onPressed: _registerWithEmail,
                                child: const Text('Register')),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (Platform.isIOS || Platform.isMacOS)
                          SignInWithAppleButton(onPressed: _signInWithApple),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
