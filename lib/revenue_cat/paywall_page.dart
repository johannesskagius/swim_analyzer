import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Import 'PlatformException' to handle purchase errors
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:swim_analyzer/auth_wrapper.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import '../home_page.dart';

class PaywallPage extends StatefulWidget {
  final AppUser? appUser;
  const PaywallPage({super.key, this.appUser});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  // This future will hold the offerings we fetch from RevenueCat.
  late Future<List<Package>> _packagesFuture;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _packagesFuture = _fetchPackages();
  }

  /// Fetches the available subscription packages from RevenueCat.
  Future<List<Package>> _fetchPackages() async {
    try {
      // Get the current Offerings from RevenueCat.
      final Offerings offerings = await Purchases.getOfferings();

      // We'll use the 'default' offering, but you could have multiple.
      final Offering? currentOffering = offerings.current;

      if (currentOffering != null &&
          currentOffering.availablePackages.isNotEmpty) {
        return currentOffering.availablePackages;
      }
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: 'Failed to fetch RevenueCat offerings',
      );
      // If fetching fails, we'll show an error message.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not load subscription plans. Please try again later.'),
          ),
        );
      }
    }
    // Return an empty list if there's an error or no packages are available.
    return [];
  }

  // This helper function centralizes the navigation logic.
  void _navigateToHome() {
    // Navigate back to the AuthWrapper. It will re-check permissions
    // and correctly direct the user to the HomePage with the provider setup.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AuthWrapper(),
      ),
          (route) => false, // Remove all previous routes.
    );
  }

  /// Handles the purchase logic when a user taps on a package.
  Future<void> _purchasePackage(Package package) async {
    if (widget.appUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot make purchase: User not logged in.')),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final purchaseResult = await Purchases.purchase(
          PurchaseParams.storeProduct(package.storeProduct));
      final CustomerInfo customerInfo = purchaseResult.customerInfo;

      if (kDebugMode) {
        print(
            'Active entitlements after purchase: ${customerInfo.entitlements.active.keys}');
      }

      final hasProSwimmer =
      customerInfo.entitlements.active.containsKey('pro_swimmer');
      final hasProCoach =
      customerInfo.entitlements.active.containsKey('pro_coach');

      if (hasProSwimmer || hasProCoach) {
        if (mounted) {
          _navigateToHome();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Purchase successful! Unlocking features.')),
          );
          _navigateToHome();
        }
      }
    } on PlatformException catch (e) {
      final PurchasesErrorCode errorCode = PurchasesErrorHelper.getErrorCode(e);

      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Purchase failed: ${e.message}')),
          );
        }
      }
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Purchase failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('An unexpected error occurred during purchase.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isPurchasing = true);

    try {
      final CustomerInfo restoredCustomerInfo =
      await Purchases.restorePurchases();

      final hasActiveEntitlement =
          restoredCustomerInfo.entitlements.active.isNotEmpty;

      if (!hasActiveEntitlement) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No active subscriptions found to restore.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your purchase has been restored.')),
          );
          _navigateToHome();
        }
      }
    } on PlatformException catch (e) {
      final PurchasesErrorCode errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Restore failed: ${e.message}')),
          );
        }
      }
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Restore failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('An unexpected error occurred during restore.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Plan'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _isPurchasing ? null : _restorePurchases,
            child: Text(
              'Restore Purchases',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Package>>(
          future: _packagesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                _isPurchasing) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.data!.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Could not load subscription plans at this time. Please check your internet connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _packagesFuture = _fetchPackages();
                          });
                        },
                        child: const Text('Retry'),
                      ),
                      if (kDebugMode)
                        ElevatedButton(
                          onPressed: () {
                            if (widget.appUser != null) {
                              _navigateToHome();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Cannot skip without a valid user.'),
                                ),
                              );
                            }
                          },
                          child: const Text('Skip to Home'),
                        )
                    ],
                  ),
                ),
              );
            }

            final packages = snapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 20),
              itemCount: packages.length,
              itemBuilder: (context, index) {
                final package = packages[index];
                final product = package.storeProduct;

                return Card(
                  margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(product.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(product.description),
                    ),
                    trailing: Text(
                      product.priceString,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap:
                    _isPurchasing ? null : () => _purchasePackage(package),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
