import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import PlatformException
import 'package:purchases_flutter/models/entitlement_info_wrapper.dart';
import 'package:purchases_flutter/models/store.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
// import 'package:url_launcher/url_launcher.dart'; // REMOVED: No longer needed
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ManageSubscriptionPage extends StatefulWidget {
  const ManageSubscriptionPage({super.key});

  @override
  State<ManageSubscriptionPage> createState() => _ManageSubscriptionPageState();
}

class _ManageSubscriptionPageState extends State<ManageSubscriptionPage> {
  CustomerInfo? _customerInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomerInfo();
  }

  // Fetches customer information from RevenueCat.
  // Includes robust error handling with Crashlytics logging and user feedback.
  Future<void> _fetchCustomerInfo() async {
    // Avoids state updates if the widget is no longer in the tree.
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      if (mounted) {
        setState(() {
          _customerInfo = customerInfo;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      // Log non-fatal error to Crashlytics for monitoring.
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Failed to fetch customer info for management');
      if (mounted) {
        setState(() => _isLoading = false);
        // Show a user-friendly message if fetching fails.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load subscription details.')),
        );
      }
    }
  }

  // Restores previous purchases for the user.
  // Now includes more specific error logging and user feedback.
  Future<void> _restorePurchases() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await Purchases.restorePurchases();
      // Refresh customer info after a successful restore.
      await _fetchCustomerInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases restored successfully.')),
        );
      }
    } catch (e, s) { // Added stack trace 's' for better debugging.
      // Log the specific error to Crashlytics.
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to restore purchases');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not restore purchases.')),
        );
      }
    } finally {
      // Ensure the loading indicator is always turned off.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openExternalSubscriptionManager() async {
    try {
      // 1. Get the customer info
      final CustomerInfo customerInfo = await Purchases.getCustomerInfo();

      // 2. Get the management URL
      final String? managementURL = customerInfo.managementURL;

      if (managementURL == null || managementURL.isEmpty) {
        // This can happen if the user has no active subscriptions
        // or if the platform (e.g., Amazon) doesn't support it.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No active subscriptions found to manage.')),
          );
        }
        return;
      }

      // 3. Launch the URL
      final Uri managementUri = Uri.parse(managementURL);
      if (await canLaunchUrl(managementUri)) {
        await launchUrl(managementUri, mode: LaunchMode.externalApplication);
      } else {
        // Handle the case where the URL can't be launched
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open subscription manager.')),
          );
        }
      }

    } on PlatformException catch (e, s) {
      // This can happen if the user is not logged in to the App Store, for example.
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: "Failed to show subscription management page",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not open subscription manager at this time.')),
        );
      }
    } catch (e, s) {
      // Handle any other generic errors
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: "Generic error in _openExternalSubscriptionManager",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An unknown error occurred.')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Subscription'),
      ),
      body: _buildBody(),
    );
  }

  // REFACTOR: Logic for what to display in the body is moved into its own function for clarity.
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Check for null or empty entitlements to decide which view to show.
    if (_customerInfo?.entitlements.active.isEmpty ?? true) {
      return _buildNoActiveSubscriptionView();
    }
    return _buildSubscriptionDetailsView();
  }

  Widget _buildNoActiveSubscriptionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mood_bad_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No Active Subscription',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'You can restore a previous purchase if you have one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _restorePurchases,
              child: const Text('Restore Purchases'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionDetailsView() {
    // Using a nullable variable with a guard clause for safety, although the build logic already ensures it's not null here.
    final activeEntitlement = _customerInfo?.entitlements.active.values.first;
    if (activeEntitlement == null) {
      // This should ideally never be reached due to the logic in `_buildBody`,
      // but it provides an extra layer of safety.
      return _buildNoActiveSubscriptionView();
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CURRENT PLAN',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatIdentifier(activeEntitlement.productIdentifier),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 32),
                _buildDetailRow(
                  'Renews on',
                  _getFormattedRenewalDate(activeEntitlement),
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  'Purchased via',
                  _formatStoreName(activeEntitlement.store),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _openExternalSubscriptionManager,
          child: const Text('Cancel or Change Plan'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _restorePurchases,
          child: const Text('Restore Purchases'),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Cancelling or changing your plan will take you to the official App Store or Google Play subscription page.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        )
      ],
    );
  }

  Widget _buildDetailRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // REFACTOR: Moved date formatting to a separate function for better testability and readability.
  // Includes error handling for date parsing.
  String _getFormattedRenewalDate(EntitlementInfo entitlement) {
    final dateString = entitlement.expirationDate;
    if (dateString == null) {
      return 'N/A';
    }
    try {
      final date = DateTime.parse(dateString);
      return DateFormat.yMMMd().format(date);
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to parse expiration date');
      return 'Invalid Date';
    }
  }

  // REFACTOR: This helper function is clean and can be kept as is.
  String _formatIdentifier(String identifier) {
    return identifier
        .split('_')
        .map((e) => e.isNotEmpty ? '${e[0].toUpperCase()}${e.substring(1)}' : '')
        .join(' ');
  }

  // REFACTOR: Changed parameter to Store enum for type safety.
  String _formatStoreName(Store store) {
    switch (store) {
      case Store.appStore:
        return 'Apple App Store';
      case Store.playStore:
        return 'Google Play Store';
      default:
        return 'Other';
    }
  }
}
