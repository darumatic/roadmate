import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';

import '../models/site.dart';

/// Link that opens a site's location in the maps application the platform
/// actually has: the `geo:` scheme on Android (native maps app, or a chooser),
/// Apple Maps on iOS, and the universal Google Maps URL on web and desktop
/// (where it opens a browser tab).
///
/// Coordinates are optional — an un-geocoded site falls back to a maps text
/// search for its [address], so every site gets a working link.
Uri mapsUri({
  required bool isWeb,
  required TargetPlatform platform,
  double? lat,
  double? lng,
  required String name,
  required String address,
}) {
  final hasPin = lat != null && lng != null;
  if (!isWeb && platform == TargetPlatform.android) {
    // geo: is an opaque scheme, so the label/query is encoded by hand.
    return hasPin
        ? Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})')
        : Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
  }
  if (!isWeb && platform == TargetPlatform.iOS) {
    return Uri.https(
      'maps.apple.com',
      '/',
      hasPin ? {'ll': '$lat,$lng', 'q': name} : {'q': address},
    );
  }
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': hasPin ? '$lat,$lng' : address,
  });
}

/// Opens [site] in the platform maps app ([mapsUri]). Returns false when
/// nothing on the device could handle the link.
Future<bool> openSiteInMaps(
  Site site, {
  bool? isWeb,
  TargetPlatform? platform,
}) {
  return launchUrl(
    mapsUri(
      isWeb: isWeb ?? kIsWeb,
      platform: platform ?? defaultTargetPlatform,
      lat: site.lat,
      lng: site.lng,
      name: site.name,
      address: site.address,
    ),
    // The maps app, not the in-app browser — and a new tab on web.
    mode: LaunchMode.externalApplication,
  );
}
