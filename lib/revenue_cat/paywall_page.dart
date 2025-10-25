import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:swim_analyzer/auth_wrapper.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class PaywallPage extends StatefulWidget {
  final AppUser? appUser;

  const PaywallPage({super.key, this.appUser});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  late Future<Map<String, List<Package>>> _offeringsFuture;
  bool _isPurchasing = false;

  // --- Style Constants ---
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color darkBlue = Color(0xFF0D47A1);
  static const Color accentColor = Color(0xFFFFD600);
  static const Color lightBlueBackground = Color(0xFFE3F2FD);
  static const Color bestValueBorderColor = accentColor;

  @override
  void initState() {
    super.initState();
    _offeringsFuture = _fetchAllOfferings();
  }

  Future<Map<String, List<Package>>> _fetchAllOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final grouped = <String, List<Package>>{};
      for (final entry in offerings.all.entries) {
        if (entry.value.availablePackages.isNotEmpty) {
          grouped[entry.key] = entry.value.availablePackages;
        }
      }
      if (grouped.isEmpty) throw Exception('No offerings found.');
      return grouped;
    } catch (e, s) {
      FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'Fetch offerings failed');
      rethrow;
    }
  }

  Future<void> _purchase(Package package) async {
    if (widget.appUser == null) {
      _showSnack('Please log in before purchasing.');
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      // Run the purchase
      final purchaserInfo = await Purchases.purchase(
        PurchaseParams.package(package),
      );

      // 🔍 Check entitlements immediately
      final entitlements = await purchaserInfo.customerInfo.entitlements.active.keys.toList();

      debugPrint('Active entitlements after purchase: $entitlements');

      if (entitlements.isNotEmpty) {
        // ✅ Purchase succeeded & entitlement active

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('🎉 Subscription Activated'),
            content: const Text(
              'Welcome aboard! Your premium features are now unlocked.',
              style: TextStyle(fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Continue'),
              ),
            ],
          ),
        );

        // Optional: fetch fresh customer info from backend to ensure sync
        final info = await Purchases.getCustomerInfo();
        debugPrint('Synced entitlements: ${info.entitlements.active.keys}');

        // Proceed to main app if still active
        if (info.entitlements.active.isNotEmpty) {
          _navigateToAuthWrapper();
        } else {
          _showSnack('Purchase completed but entitlement not yet active.');
        }
      } else {
        _showSnack('Purchase successful, but no active entitlement found.');
      }
    } on PlatformException catch (e, s) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Purchase failed');
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        _showSnack('Purchase cancelled.');
      } else {
        _showSnack('Purchase failed: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }


  void _navigateToAuthWrapper() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (_) => false,
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _restore() async {
    setState(() => _isPurchasing = true);
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      if (info.entitlements.active.isEmpty) {
        _showSnack('No active subscriptions found to restore.');
      } else {
        _showSnack('Purchases restored successfully!');
        _navigateToAuthWrapper();
      }
    } catch (e, s) {
      if (!mounted) return;
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Restore failed');
      _showSnack('Restore failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _isPurchasing = true);
    try {
      await Purchases.logOut();
      await FirebaseAuth.instance.signOut();
      _navigateToAuthWrapper();
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Logout failed');
      _showSnack('Could not switch account. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryBlue, darkBlue],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Unlock Pro Features'),
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (!_isPurchasing)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'restore') {
                    _restore();
                  } else if (value == 'logout') {
                    _logout();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'restore',
                    child: Text('Restore Purchases'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('Switch Account'),
                  ),
                ],
                icon: const Icon(Icons.more_vert, color: Colors.white),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
            kDebugMode ? IconButton(onPressed: () async {
              await Purchases.logOut();
              await Purchases.logIn(widget.appUser!.id);
              Navigator.pop(context);
            }, icon: Icon(Icons.exit_to_app)):const SizedBox.shrink()
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<Map<String, List<Package>>>(
            future: _offeringsFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting ||
                  _isPurchasing) {
                return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ));
              }

              if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                debugPrint("Paywall Error: ${snap.error}");
                return _buildError(() =>
                    setState(() => _offeringsFuture = _fetchAllOfferings()));
              }

              final offerings = snap.data!;
              final solo = offerings.entries
                  .where((e) => e.key.toLowerCase().contains('single_default'))
                  .expand((e) => e.value)
                  .toList();
              final team = offerings.entries
                  .where((e) => e.key.toLowerCase().contains('team_default'))
                  .expand((e) => e.value)
                  .toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  _glassHeader(),
                  const SizedBox(height: 24),
                  if (team.isNotEmpty) ...[
                    _metaSection(
                      icon: Icons.groups,
                      title: 'Team & Club Plans',
                      desc:
                      'Manage multiple swimmers, track progress, and collaborate effectively.',
                    ),
                    const SizedBox(height: 8),
                    ...team.map(_planCard),
                    const SizedBox(height: 32),
                  ],
                  if (solo.isNotEmpty) ...[
                    _metaSection(
                      icon: Icons.person,
                      title: 'Individual Plans',
                      desc:
                      'For swimmers & coaches focused on personal performance analysis.',
                    ),
                    const SizedBox(height: 8),
                    ...solo.map(_planCard),
                    const SizedBox(height: 32),
                  ],
                  const SizedBox(height: 16),
                  _metaSection(
                    icon: Icons.switch_account,
                    title: 'Individual Plans',
                    desc:
                    'For swimmers & coaches focused on personal performance analysis.',
                  ),
                  _buildUserProfileInfo(),
                  const SizedBox(height: 16),
                  _footerNote(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _glassHeader() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                const Icon(Icons.show_chart_rounded,
                    color: Colors.white, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Go Pro with Swim Analyzer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2), blurRadius: 5)
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Unlock advanced analytics, unlimited history, and exclusive features to reach your peak performance.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// **NEW**: Displays the currently logged-in user's email.
  ///
  /// This widget provides important context to the user, confirming which
  /// account they are about to make a purchase for. It's styled to blend
  /// in with the existing UI.
  Widget _buildUserProfileInfo() {
    // If for some reason the appUser is null, don't show anything.
    if (widget.appUser == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_circle_outlined,
              color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              // Assuming AppUser has an 'email' property.
              widget.appUser!.email,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaSection({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              Icon(icon, color: Colors.white),
            ],
          ),
          const SizedBox(height: 6),
          Text(desc,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }

  Widget _planCard(Package package) {
    final storeProduct = package.storeProduct;
    final isAnnual = package.packageType == PackageType.annual;
    final isBestValue = isAnnual;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isBestValue
            ? const BorderSide(color: bestValueBorderColor, width: 2.5)
            : BorderSide.none,
      ),
      color: isBestValue ? lightBlueBackground.withOpacity(0.9) : Colors.white,
      child: InkWell(
        onTap: _isPurchasing ? null : () => _purchase(package),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      storeProduct.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isBestValue ? primaryBlue : Colors.black87,
                      ),
                    ),
                  ),
                  if (isBestValue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: bestValueBorderColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'BEST VALUE',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                storeProduct.description,
                style: TextStyle(
                  fontSize: 14,
                  color: isBestValue
                      ? primaryBlue.withOpacity(0.9)
                      : Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                storeProduct.priceString,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: primaryBlue,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  elevation: isBestValue ? 2 : 0,
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isPurchasing ? null : () => _purchase(package),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: Text(_isPurchasing
                    ? 'Processing...'
                    : 'Get ${isAnnual ? "Annual" : "Monthly"} Plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
      child: Column(
        children: [
          const Divider(color: Colors.white30, thickness: 1),
          const SizedBox(height: 16),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
              children: [
                const TextSpan(
                    text:
                    'Subscriptions auto-renew unless canceled at least 24 hours before the end of the current period. Manage your subscription in your '),
                const TextSpan(
                    text: 'App Store or Google Play account settings',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.yellow[700], size: 48),
            const SizedBox(height: 16),
            const Text(
              'Oops! Could not load subscription plans.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: darkBlue,
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}