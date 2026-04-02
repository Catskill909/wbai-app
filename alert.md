# Network Connectivity Check + Offline Modal Plan

## Objectives
- Ensure the app checks for actual internet access at startup and during runtime.
- If offline, present a modern dark-mode modal:
  - Title: “You’re Offline”
  - Body: “The radio needs internet to play. Please reconnect and try again.”
  - Actions: Retry, Dismiss (and optionally, Open Settings)
- Integrate with existing architecture (GetIt + BLoC), styling (Oswald/Poppins), and dark theme.

## Where to Integrate
- Root entry: `lib/main.dart` inside `WPFWRadioApp`.
- Provide a connectivity BLoC/Cubit at the top-level (sibling to `StreamBloc`) so it’s available app-wide.
- Listen for connectivity changes via a global `BlocListener` that shows/hides a modal above all pages.

## Architecture
- __Service__: `ConnectivityService`
  - Uses `connectivity_plus` for network type changes.
  - Verifies “internet access” by attempting a lightweight HTTP/HEAD request to a known 204 endpoint (e.g., `https://www.google.com/generate_204`) via `dio` (already in dependencies). This avoids false-positives (e.g., captive portals, offline DNS).
  - Exposes a stream of `ConnectivityStatus { online, offline }` and a method `checkNow()`.

- __State__: `ConnectivityCubit`
  - Holds `ConnectivityState { status: online|offline, lastCheckedAt, firstRunShown }`.
  - Subscribes to `ConnectivityService` streams; performs an initial `checkNow()` on creation.
  - Emits first state quickly (cached/last-known) then confirms with the 204 probe.

- __Presentation__: `OfflineModal`
  - A dark-mode, full-screen or centered dialog consistent with `AppTheme.darkTheme` and `AppTextStyles`.
  - Title uses Oswald; body and buttons use Poppins.
  - Actions:
    - Retry: triggers `ConnectivityCubit.checkNow()`.
    - Dismiss: closes modal. If still offline, we won’t auto-reopen until the next connectivity change or app foreground; playback actions will still be guarded.
    - Optional: Open Settings (platform-conditional) using `url_launcher`.

## Placement Details
- __Provide Cubit__: wrap `MaterialApp` provider in `lib/main.dart`:
  - Replace `BlocProvider` with `MultiBlocProvider`.
  - Add `BlocProvider(create: (_) => getIt<ConnectivityCubit>()..initialize())`.

- __Global Listener__: wrap `MaterialApp` with a `BlocListener<ConnectivityCubit, ConnectivityState>`:
  - On `offline` and if not already visible, show modal via `showGeneralDialog` with `rootNavigator: true`.
  - On `online`, ensure the modal is dismissed if visible.

- __DI Registration__: `lib/core/di/service_locator.dart`
  - Register `ConnectivityService` as a lazy singleton.
  - Register `ConnectivityCubit` as a factory (depends on service).

## Styling Guidelines
- Base color: use scaffold background `Color(0xFF0F0404)`.
- Card/modal surface: slightly lighter dark (e.g., `Color(0xFF161616)`), with subtle shadow.
- Title: `AppTextStyles.showTitle` (Oswald) or `headlineSmall`.
- Body: `AppTextStyles.bodyMedium`.
- Buttons: `AppTextStyles.button`.
- Icons: `Icons.wifi_off` in white; add a small warning accent if desired.

## Behavior Nuances
- __Startup__: If offline at first run, show modal once. If user Dismisses, don’t auto-reopen until a connectivity state change occurs or the user presses Play (in which case we can re-check and reshow).
- __Runtime Changes__: If the app transitions from online→offline, show modal. If offline→online, dismiss modal.
- __Playback Guard__: In `HomePage` (`lib/presentation/pages/home_page.dart`), disable/ignore StartStream events when offline; show a small SnackBar only if the modal is not currently visible (prevents UX noise).
- __Exponential Backoff__: `ConnectivityService` may retry the internet probe on a backoff schedule when offline to limit network chatter.
- __iOS/Android Considerations__: Use a timeout (e.g., 2–3s) for the 204 probe to avoid hanging. Avoid over-probing during background.

## Files To Add
- `lib/core/services/connectivity_service.dart`
  - Listens to `Connectivity().onConnectivityChanged`.
  - `Future<bool> hasInternet()` using `dio` HEAD to 204 endpoint with timeout.
  - `Stream<ConnectivityStatus>` combining type + internet probe.

- `lib/presentation/bloc/connectivity_cubit.dart`
  - States: `ConnectivityState { isOnline: bool, checking: bool, firstRun: bool }`.
  - Methods: `initialize()`, `checkNow()`, `dispose()`.

- `lib/presentation/widgets/offline_modal.dart`
  - Stateless/Stateful dialog with title, body text, icon, and buttons.
  - Reusable, so we can present it from any context.

## Files To Update
- `lib/core/di/service_locator.dart`
  - `getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService(dio: getIt<Dio>()));`
  - `getIt.registerFactory<ConnectivityCubit>(() => ConnectivityCubit(service: getIt<ConnectivityService>()));`
  - If `Dio` isn’t registered yet, register a base instance.

- `lib/main.dart`
  - Provide `ConnectivityCubit` via `MultiBlocProvider`.
  - Wrap `MaterialApp` with `BlocListener<ConnectivityCubit, ConnectivityState>` to present/dismiss `OfflineModal`.

- `lib/presentation/pages/home_page.dart`
  - Read `ConnectivityCubit` state to disable the big Play/Pause button when offline.
  - If user taps Play while offline and modal is not visible, `showDialog` or trigger `ConnectivityCubit.checkNow()` then show the modal.

## Pseudocode Sketches
```dart
// main.dart
return MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => getIt<StreamBloc>()),
    BlocProvider(create: (_) => getIt<ConnectivityCubit>()..initialize()),
  ],
  child: BlocListener<ConnectivityCubit, ConnectivityState>(
    listenWhen: (p, n) => p.isOnline != n.isOnline,
    listener: (context, state) {
      if (!state.isOnline) {
        showGeneralDialog(
          context: context,
          barrierColor: Colors.black54,
          barrierDismissible: true,
          pageBuilder: (_, __, ___) => const OfflineModal(),
        );
      } else {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    },
    child: MaterialApp(...),
  ),
);
```

```dart
// connectivity_service.dart
class ConnectivityService {
  final Connectivity _conn = Connectivity();
  final Dio _dio;
  ConnectivityService({required Dio dio}) : _dio = dio;

  Future<bool> hasInternet() async {
    try {
      final res = await _dio.head('https://www.google.com/generate_204', options: Options(receiveTimeout: Duration(seconds: 2), sendTimeout: Duration(seconds: 2)));
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
```

```dart
// offline_modal.dart (visual cues only)
class OfflineModal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: const Color(0xFF161616),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text("You’re Offline", style: AppTextStyles.showTitle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text("The radio needs internet to play. Please reconnect and try again.", style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => context.read<ConnectivityCubit>().checkNow(), child: Text('Retry', style: AppTextStyles.button))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: Text('Dismiss', style: AppTextStyles.button))),
              ],
            )
          ],
        ),
      ),
    );
  }
}
```

## Edge Cases & Tests
- Airplane mode on launch → modal appears; turning Wi‑Fi on → modal dismisses automatically.
- Captive portal returns HTTP 200 with body (no 204) → treat as offline until a valid HEAD/204 or any successful known host check.
- Background/foreground transitions → perform a quick recheck with throttling.
- iOS lockscreen audio controls unaffected; playback guarded when offline.

## Rollout Steps
1. Add files (`ConnectivityService`, `ConnectivityCubit`, `OfflineModal`).
2. Register in DI and provide cubit in `main.dart`.
3. Add global listener and modal presentation.
4. Guard playback actions in `HomePage` when offline.
5. Manual test on iOS/Android devices and simulators/emulators.
