import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? userLocation;
  LatLng? _selectedMarkerPoint;
  String selectedAddress = '';
  final mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    // Step 1: Check if location service is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      _showError("Please enable location services.");
      return;
    }

    // Step 2: Check current permission
    LocationPermission permission = await Geolocator.checkPermission();

    // Step 3: If denied, then ask user via dialog before requesting
    if (permission == LocationPermission.denied) {
      bool userAgreed = await _showLocationPermissionExplainDialog();
      if (!userAgreed) {
        _showError("Location permission was not granted.");
        return;
      }

      // Now request permission
      permission = await Geolocator.requestPermission();
    }

    // Step 4: Handle denied forever
    if (permission == LocationPermission.deniedForever) {
      _showPermissionDialog();
      return;
    }

    // Step 5: If granted, get current position
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
      });
    } else {
      _showError("Location permission was not granted.");
    }
  }

  Future<bool> _showLocationPermissionExplainDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (_) => AlertDialog(
                title: const Text("Location Permission"),
                content: const Text(
                  "We need your location to show your position on the map. Do you want to allow it?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("No"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Yes"),
                  ),
                ],
              ),
        ) ??
        false;
  }

  // Show error as snackbar or alert
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // Show permission dialog for deniedForever
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Permission Needed"),
            content: const Text(
              "Location permission is permanently denied. Please enable it from app settings.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Geolocator.openAppSettings();
                },
                child: const Text("Open Settings"),
              ),
            ],
          ),
    );
  }

  Future<void> _onTapMap(LatLng point) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );

      Placemark place = placemarks.first;

      // Clean and filter out unwanted or empty values
      List<String?> addressParts =
          [
                place.name,
                place.street,
                place.subLocality,
                place.locality,
                place.postalCode,
                place.administrativeArea,
                place.country,
              ]
              .where(
                (part) =>
                    part != null &&
                    part.isNotEmpty &&
                    !part.contains(RegExp(r'^\w{4}\+\w{3}$')),
              ) // remove Plus Code
              .toList();

      String cleanAddress = addressParts.join(', ');

      setState(() {
        selectedAddress = cleanAddress;
        _selectedMarkerPoint = point;
        debugPrint("🗺️ Address: $cleanAddress");
      });
      // 🔍 Debug print of full breakdown
      debugPrint('''
📍 Selected Location Details:
- Name (house/building): ${place.name}
- Street/Road: ${place.street}
- Area (subLocality): ${place.subLocality}
- City (locality): ${place.locality}
- Postal Code: ${place.postalCode}
- Division (adminArea): ${place.administrativeArea}
- Country: ${place.country}
- Full Address: $cleanAddress
''');

      showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text("Selected Location"),
              content: Text(selectedAddress),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
      );
    } catch (e) {
      print('❌ Error getting address: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map Example')),
      body:
          userLocation == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: userLocation!,
                  initialZoom: 16,
                  onTap: (tapPosition, point) => _onTapMap(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: userLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                      // ✅ Selected marker
                      if (_selectedMarkerPoint != null)
                        Marker(
                          point: _selectedMarkerPoint!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap contributors',
                        onTap:
                            () => launchUrl(
                              Uri.parse('https://openstreetmap.org/copyright'),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
    );
  }
}
