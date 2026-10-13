# Plan: use this package without Flutter Bloc state

## Goal

Any app can drop in `mdsoft_google_map_routing` and get routing, live location, and the map. The host app does not have to use `flutter_bloc`, `GoogleMapCubit`, or `GoogleMapState`.

The widget keeps its own state inside the package. The host listens with callbacks or a small controller. Apps that already use Bloc can keep using the cubit. Apps that use `setState`, Provider, Riverpod, GetX, or no state library can use the same widget.

## What is broken today

`MdSoftGoogleMapRouting` always creates a cubit and rebuilds only through Bloc:

```47:50:lib/google_map_routing.dart
    return BlocProvider(
      create: (context) => GoogleMapCubit(),
      child: BlocConsumer<GoogleMapCubit, GoogleMapState>(
```

`GoogleMapWidget` then requires that cubit:

```147:147:lib/google_map_routing.dart
  final GoogleMapCubit cubit;
```

That locks every user to this package's state:

- The public library exports the cubit, so the public contract is Bloc states.
- Errors and "destination reached" are toasts inside the listener. The host cannot handle them in its own state.
- Markers, polylines, and the camera live as fields on the cubit. Nothing else can own that data.
- `GoogleMapConfig.tripStatusController` is one static stream for the whole app. Two maps share one trip status.
- `flutter_bloc` is a required dependency (`^9.1.1`). A version clash with the host app blocks the package even when the host never reads the cubit.
- The widget always builds its own `BlocProvider`. The host cannot pass its own controller in.

Routing, sockets, and the background location service are fine. The problem is that the only door into them is `GoogleMapCubit`.

## Target shape

```
Host app (any state, or none)
        |
        |  callbacks + optional MdSoftMapController
        v
MdSoftGoogleMapRouting          (public widget, same constructor as today)
        |
        v
MapRoutingEngine                (location, route, markers, camera, socket)
        |
        +--> ListenableBuilder  (map UI, no Bloc)
        |
        +--> GoogleMapCubit     (optional adapter, same states as today)
```

The engine is a plain Dart class. It does not extend `Cubit` and does not import `flutter_bloc`. It notifies with Flutter's `ChangeNotifier`, which ships with the Flutter SDK. No extra state package is required to use the map.

## Public API the host will use

Existing constructor arguments stay: `startLocation`, `endLocation`, `waypoints`, `pointsName`, `isUser`, `carPosstion`, `tripId`, `driverId`, `isViewTrip`, `mapStyle`. Current call sites keep compiling.

New optional arguments:

| Argument | Role |
| --- | --- |
| `controller` | Optional `MdSoftMapController`. If omitted, the widget creates and disposes one. |
| `onError` | `void Function(MdSoftMapError error)`. Replaces the forced toast when the host wants its own UI. |
| `onDestinationReached` | `void Function(int routeStep)`. |
| `onTripStatus` | `void Function(TripStatus status)`. Per map, not the static stream. |
| `showDefaultToasts` | Default `true` so current toast behavior stays. Set `false` to handle errors only in callbacks. |

Controller surface (read-only for the host):

- `markers`, `polylines`, `cameraPosition`
- `isTracking`, `hasReachedDestination`
- `tripStatus` stream for this map only
- `stopTracking()`
- `Listenable`, so Provider / Riverpod / `AnimatedBuilder` can watch it without Bloc

The host never calls `context.read<GoogleMapCubit>()`.

Example for an app that cannot use this package's state:

```dart
MdSoftGoogleMapRouting(
  startLocation: start,
  endLocation: end,
  carPosstion: car,
  tripId: tripId,
  isUser: true,
  showDefaultToasts: false,
  onError: (error) => mySnackBar(error.message),
  onDestinationReached: (_) => myState.completeTrip(),
  onTripStatus: (status) => myState.setTrip(status),
)
```

Example for an app that already has Bloc and wants the old states:

```dart
BlocBuilder<GoogleMapCubit, GoogleMapState>(
  bloc: mapController.cubit, // adapter, optional
  builder: (context, state) { /* unchanged states */ },
)
```

`GoogleMapCubit` and `GoogleMapState` stay exported in this change so current imports do not break. They become a wrapper over the engine. New code should use the controller.

## Work steps

### 1. Extract the engine

Move the behavior out of `GoogleMapCubit` into `lib/src/controller/map_routing_engine.dart`.

Move these methods as-is, still calling the same repo, location service, camera service, and socket:

- `getLocationMyCurrentLocation`
- `getMyStreemLocation`
- `getDirectionsRoute` / route loading
- `getMapStyle`
- marker and polyline updates
- destination check
- socket init and background `updateLocation`

Replace `emit(...)` with updates on one immutable `MapViewData` plus `notifyListeners()`. Error and destination events go out through callbacks on the engine, not through Bloc state classes.

`GoogleMapCubit` becomes a thin adapter: it listens to the engine and emits the same `GoogleMapState` subclasses it emits today (`GetLocationErrorState`, `GetRoutesFailureState`, `DestinationReachedState`, and the success states). No second copy of the routing logic.

### 2. Controller

Add `MdSoftMapController` in `lib/src/controller/md_soft_map_controller.dart`.

- Owns one `MapRoutingEngine`.
- Exposes the read-only view and `stopTracking()`.
- Optionally exposes `GoogleMapCubit get cubit` for hosts that still want Bloc.
- `dispose()` cancels the position stream, closes the cubit if it was created, and stops tracking for the driver flow the same way `_stopTracking()` does now.

### 3. Widget uses the controller, not the cubit

In `lib/google_map_routing.dart`:

- If `controller` is null, create one in a `StatefulWidget` state and dispose it. The host can stay a `StatelessWidget`.
- Rebuild the map with `ListenableBuilder` (or `AnimatedBuilder`) on the controller.
- Pass markers, polylines, and the camera from `MapViewData` into `GoogleMap`.
- Keep `GoogleMapWidget` as the map `StatefulWidget` inside the package. That state is an implementation detail (map controller, lifecycle, background service). The host does not write it.
- Move the `BlocConsumer` listener (toasts, destination message) behind `showDefaultToasts`. Always invoke `onError`, `onDestinationReached`, and `onTripStatus` as well.
- Remove the requirement that `GoogleMapWidget` takes a `GoogleMapCubit`.

`BlocProvider` is created only when the host asks for the cubit adapter. A host that never touches Bloc does not get a `BlocProvider` in the tree.

### 4. Per-map trip status

Keep `GoogleMapConfig.tripStatusListener` so the example and README keep working.

Also give each controller its own broadcast stream. The widget's user-flow listener (`TripStatus.driverArrived` redraws the route) subscribes to that map's stream. Document that the static stream is global and the controller stream is the one to use when the screen has more than one map.

### 5. Exports and dependencies

- Export the controller and `MapViewData` / `MdSoftMapError` from `lib/google_map_routing.dart`.
- Keep exporting the cubit for this version.
- Leave `flutter_bloc` in `pubspec.yaml` for the adapter. A later major version can move it to an optional import if we split the adapter into its own library file that hosts import only when they want Bloc. Do not remove it in this change.

### 6. Example

Add a second screen in `example/` that uses only callbacks and no `BlocBuilder` / `context.read`. Keep the current screen so the Bloc path still runs.

### 7. Docs

Update `README.md` with the callback example next to the current widget example. Note that `GoogleMapCubit` remains supported and is no longer required.

## Out of scope for this change

- Renaming `carPosstion` (keep it; a new `carPosition` alias can wait).
- Rewriting socket, polyline, or background-service behavior.
- The placeholder plugin block in `pubspec.yaml` (`some_platform` / `somePluginClass`).
- Making `flutter_bloc` a non-dependency. That is a later major version after the controller is the documented API.

## Done when

- A screen that never imports `flutter_bloc` can show the route, track location, and receive error, destination, and trip-status callbacks.
- The current `MdSoftGoogleMapRouting(...)` call in `example/lib/main.dart` still builds and still shows the default toasts.
- `GoogleMapCubit` state classes still emit for a host that opts into the adapter.
- Two controllers on one app do not share trip status.
- `flutter analyze` on `lib/` and `example/` reports no new issues.
