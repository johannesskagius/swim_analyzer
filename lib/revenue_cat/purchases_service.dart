import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// --- (Optional but recommended) Store your API keys in a separate file ---
// Create a file like lib/services/api_keys.dart and add:
// const appleApiKey = 'appl_YourAppleKey';
// const googleApiKey = 'goog_YourGoogleKey';
// Then import it here. For this example, I'll hardcode them.

class PurchasesService {
  static const _appleApiKey = 'appl_JtAuGFwkhYjDnbaUJhWhscOZzSW';
  static const _googleApiKey = 'goog_YOUR_REVENUECAT_GOOGLE_API_KEY';

  /// Initializes the RevenueCat SDK with the correct API key for the platform.
  static Future<void> initialize() async {
    // Enable debug logs for development builds.
    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.debug);
    }

    late PurchasesConfiguration configuration;
    if (defaultTargetPlatform == TargetPlatform.android) {
      configuration = PurchasesConfiguration(_googleApiKey);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      configuration = PurchasesConfiguration(_appleApiKey);
    } else {
      // Unsupported platform
      return;
    }
    await Purchases.configure(configuration);
  }

  /// Identifies the user with RevenueCat by their unique app user ID.
  /// This links all their purchase history to their account.
  static Future<void> identifyUser(String appUserId) async {
    try {
      await Purchases.logIn(appUserId);
    } catch (e) {
      // Handle errors, e.g., log to Crashlytics
    }
  }

  /// Resets the RevenueCat user ID when the user logs out.
  /// This is crucial for switching accounts.
  static Future<void> logout() async {
    try {
      await Purchases.logOut();
    } catch (e) {
      // Handle errors
    }
  }

  /// Checks if the current user has any active entitlements.
  static Future<bool> hasActiveEntitlements() async {
    try {
      final CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      // Using `isNotEmpty` is a safe way to check for any active entitlement.
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      // If there's an error fetching customer info, assume no entitlements.
      return false;
    }
  }
}
