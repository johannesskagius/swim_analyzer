import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:swim_analyzer/auth_wrapper.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

// Consider adding a package like 'simple_gradient_text' for gradient text effects
// import 'package:simple_gradient_text/simple_gradient_text.dart';

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
  static const Color primaryBlue = Color(0xFF1565C0); // Existing primary
  static const Color darkBlue = Color(0xFF0D47A1); // Existing dark
  static const Color accentColor =
      Color(0xFFFFD600); // Vibrant Yellow/Gold for CTA
  static const Color lightBlueBackground =
      Color(0xFFE3F2FD); // Light background for best value card
  static const Color bestValueBorderColor =
      accentColor; // Border for best value card

  @override
  void initState() {
    super.initState();
    _offeringsFuture = _fetchAllOfferings();
  }

  Future<Map<String, List<Package>>> _fetchAllOfferings() async {
    // ... (logic remains the same)
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
    // ... (logic remains the same)
    if (widget.appUser == null) {
      _showSnack('Please log in before purchasing.');
      return;
    }
    setState(() => _isPurchasing = true);
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      _navigateToAuthWrapper();
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) !=
          PurchasesErrorCode.purchaseCancelledError) {
        FirebaseCrashlytics.instance
            .recordError(e, StackTrace.current, reason: 'Purchase failed');
        _showSnack('Purchase failed: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  void _navigateToAuthWrapper() {
    // ... (logic remains the same)
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (_) => false,
    );
  }

  void _showSnack(String msg) {
    // ... (logic remains the same)
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _restore() async {
    // ... (logic remains the same)
    setState(() => _isPurchasing = true); // Show loading during restore
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return; // Check mounted state after await
      if (info.entitlements.active.isEmpty) {
        _showSnack('No active subscriptions found to restore.');
      } else {
        _showSnack('Purchases restored successfully!');
        _navigateToAuthWrapper(); // Navigate if restore was successful
      }
    } catch (e, s) {
      if (!mounted) return; // Check mounted state after await
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Restore failed');
      _showSnack('Restore failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isPurchasing = false); // Hide loading
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Enhanced Gradient
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryBlue, darkBlue],
          // Same colors, maybe adjust stops if needed
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        // Optional: Add a subtle noise texture overlay if desired
        // image: DecorationImage(image: AssetImage('assets/noise.png'), repeat: ImageRepeat.repeat, opacity: 0.05),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Unlock Pro Features'),
          // Slightly more engaging title
          titleTextStyle: const TextStyle(
            // Ensure title style is consistent
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          // Ensure back button is white
          actions: [
            TextButton(
              onPressed: _isPurchasing ? null : _restore,
              child: const Text('Restore Purchases',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8), // Add padding
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<Map<String, List<Package>>>(
            future: _offeringsFuture,
            builder: (ctx, snap) {
              // Show loader while purchasing OR loading offerings
              if (snap.connectionState == ConnectionState.waiting ||
                  _isPurchasing) {
                return const Center(
                    child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ));
              }

              if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                debugPrint("Paywall Error: ${snap.error}"); // Log the error
                return _buildError(() =>
                    setState(() => _offeringsFuture = _fetchAllOfferings()));
              }

              final offerings = snap.data!;
              // Simplified grouping (adjust keys if necessary)
              final solo = offerings.entries
                  .where((e) => e.key.toLowerCase().contains(
                      'single_default') /*|| e.key.toLowerCase().contains('default')*/)
                  .expand((e) => e.value) // Flatten the list of packages
                  .toList();
              final team = offerings.entries
                  .where((e) => e.key.toLowerCase().contains(
                      'team_default') /*|| e.key.toLowerCase().contains('support')*/)
                  .expand((e) => e.value)
                  .toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                // Consistent padding
                children: [
                  _glassHeader(),
                  const SizedBox(height: 24), // Increased spacing
                  // --- Team Section ---
                  if (team.isNotEmpty) ...[
                    _metaSection(
                      icon: Icons.groups_rounded, // Updated icon
                      title: 'Team & Club Plans',
                      desc:
                          'Manage multiple swimmers, track progress, and collaborate effectively.',
                    ),
                    const SizedBox(height: 8),
                    ...team.map(_planCard),
                    const SizedBox(height: 32), // Increased spacing
                  ],
                  // --- Solo Section ---
                  if (solo.isNotEmpty) ...[
                    _metaSection(
                      icon: Icons.person_outline_rounded, // Updated icon
                      title: 'Individual Plans',
                      desc:
                          'For swimmers & coaches focused on personal performance analysis.',
                    ),
                    const SizedBox(height: 8),
                    ...solo.map(_planCard),
                    const SizedBox(height: 32), // Increased spacing
                  ],
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
      margin: const EdgeInsets.only(top: 12), // Only top margin
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20), // Slightly larger radius
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          // Slightly more blur
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            // Adjusted padding
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05)
                ], // Adjusted opacity
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.white.withOpacity(0.2)), // Adjusted border
            ),
            child: Column(
              children: [
                const Icon(Icons.show_chart_rounded,
                    color: Colors.white, size: 36),
                // Added Icon
                const SizedBox(height: 12),
                Text(
                  'Go Pro with Swim Analyzer', // More direct headline
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24, // Larger font
                    fontWeight: FontWeight.bold, // Bolder
                    shadows: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2), blurRadius: 5)
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Unlock advanced analytics, unlimited history, and exclusive features to reach your peak performance.',
                  // Updated description
                  style: TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                  // Slightly larger font
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaSection({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    // Keep this simple and clean
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          // Larger title
          const SizedBox(height: 6),
          Text(desc,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.4)),
          // Larger description
        ],
      ),
    );
  }

  Widget _planCard(Package package) {
    final storeProduct = package.storeProduct;

    // Determine 'best value' based on identifier or duration (safer than title)
    final isAnnual = package.packageType == PackageType.annual;
    final isBestValue = isAnnual; // Assuming annual is always best value

    return Card(
      // Use Card widget
      elevation: 4,
      // Add subtle elevation
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        // Add border for best value
        side: isBestValue
            ? const BorderSide(color: bestValueBorderColor, width: 2.5)
            : BorderSide.none,
      ),
      color: isBestValue ? lightBlueBackground.withOpacity(0.9) : Colors.white,
      // Different bg for best value
      child: InkWell(
        // Make the card tappable (optional, can trigger purchase)
        onTap: _isPurchasing ? null : () => _purchase(package),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20), // Increased padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch button
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    storeProduct.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18, // Larger title
                      color: isBestValue ? primaryBlue : Colors.black87,
                    ),
                  ),
                  if (isBestValue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4), // Adjusted padding
                      decoration: BoxDecoration(
                        color: bestValueBorderColor, // Use accent color
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'BEST VALUE',
                        style: TextStyle(
                          color: Colors.black87, // Dark text on yellow
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
                      : Colors.black54, // Adjusted color
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                storeProduct.priceString,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20, // Larger price
                  color: primaryBlue,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                // Use ElevatedButton.icon
                style: ElevatedButton.styleFrom(
                  elevation: isBestValue ? 2 : 0,
                  // More elevation for best value CTA
                  backgroundColor: accentColor,
                  // Use Accent Color for CTA
                  foregroundColor: Colors.black87,
                  // Text color on accent
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  // Larger padding
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                    // Ensure text style consistency
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Disable button while purchasing
                onPressed: _isPurchasing ? null : () => _purchase(package),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                // Add Icon
                label: Text(// Dynamic and clearer button text
                    _isPurchasing
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
      // Adjusted padding
      child: Column(
        children: [
          const Divider(color: Colors.white30, thickness: 1),
          // Thicker divider
          const SizedBox(height: 16),
          // RichText for potential links later
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
              // Slightly larger font
              children: [
                const TextSpan(
                    text:
                        'Subscriptions auto-renew unless canceled at least 24 hours before the end of the current period. Manage your subscription in your '),
                // TODO: Add links to App Store/Play Store account settings if possible
                const TextSpan(
                    text: 'App Store or Google Play account settings',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Optional: Links to Terms & Privacy
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.center,
          //   children: [
          //     TextButton(onPressed: () {}, child: Text('Terms of Service', style: TextStyle(color: Colors.white70, fontSize: 12))),
          //     Text('|', style: TextStyle(color: Colors.white70, fontSize: 12)),
          //     TextButton(onPressed: () {}, child: Text('Privacy Policy', style: TextStyle(color: Colors.white70, fontSize: 12))),
          //   ],
          // )
        ],
      ),
    );
  }

  Widget _buildError(VoidCallback retry) {
    return Center(
      child: Padding(
        // Add padding around error message
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.yellow[700], size: 48),
            // Error Icon
            const SizedBox(height: 16),
            const Text(
              'Oops! Could not load subscription plans.',
              textAlign: TextAlign.center, // Center text
              style:
                  TextStyle(color: Colors.white, fontSize: 16), // Larger text
            ),
            const SizedBox(height: 12),
            const Text(
              'Please check your internet connection and try again.',
              // Helpful hint
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              // Add icon to retry button
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: darkBlue, // Match text color
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12), // Adjust padding
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
