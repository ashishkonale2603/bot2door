import 'package:flutter/material.dart';
import 'dart:async'; // Make sure 'dart:async' is imported for Completer
import '../services/api_service.dart';// Import the API service
import 'package:flutter_tts/flutter_tts.dart'; // Import the TTS package

// Enum to manage the state of the delivery person's UI
enum DeliveryFlowState {
  welcome,
  awaitingNotification,
  otpReady,
  completed,
  error,
}

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() => _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> with SingleTickerProviderStateMixin {
  DeliveryFlowState _currentState = DeliveryFlowState.welcome;
  String _spokenOtp = "";
  String _errorMessage = "";
  Timer? _pollingTimer;
  
  final ApiService _apiService = ApiService();
  final FlutterTts _flutterTts = FlutterTts(); // Initialize TTS

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    // Configure TTS settings
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.4); // Speak a bit slower
    _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startDeliveryProcess() async {
    setState(() {
      _currentState = DeliveryFlowState.awaitingNotification;
      _errorMessage = "";
    });

    try {
      await _apiService.startDelivery();
      _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        final status = await _apiService.checkStatus();
        if (status == 'otp_ready') {
          timer.cancel();
          _fetchAndSpeakOtp();
        }
      });
    } catch (e) {
      setState(() {
        _currentState = DeliveryFlowState.error;
        _errorMessage = "Could not connect to the server. Please try again.";
      });
    }
  }
  
  Future<void> _cancelDelivery() async {
    _pollingTimer?.cancel(); // Stop polling immediately
    
    try {
      await _apiService.cancelDelivery(); // Tell backend to cancel
      setState(() {
        _currentState = DeliveryFlowState.welcome; // Go back to home
      });
    } catch (e) {
      // If cancellation fails, just go back to welcome
      setState(() {
        _currentState = DeliveryFlowState.welcome;
        _errorMessage = "Could not cancel. Resetting.";
      });
    }
  }
  
  // --- THIS FUNCTION CONTAINS THE FIX ---
  Future<void> _fetchAndSpeakOtp() async {
    try {
      final otp = await _apiService.getSpokenOtp();
      setState(() {
        _currentState = DeliveryFlowState.otpReady;
        _spokenOtp = otp;
      });

      // 1. Create a Completer to wait for TTS
      final Completer<void> ttsCompleter = Completer();
      
      // 2. Tell the TTS engine to call us when it's done
      _flutterTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      });

      // 3. Start speaking
      await _flutterTts.speak(_spokenOtp);

      // 4. Wait here until the setCompletionHandler is called
      await ttsCompleter.future; 
      
      // --- The 4-second hardcoded delay is now gone ---
      
      // 5. Now that speaking is *actually* finished, move on
      if (mounted) {
        setState(() => _currentState = DeliveryFlowState.completed);
        await Future.delayed(const Duration(seconds: 3)); // Keep "Completed" for 3s
        if (mounted) {
          setState(() => _currentState = DeliveryFlowState.welcome);
        }
      }
    } catch (e) {
       setState(() {
        _currentState = DeliveryFlowState.error;
        _errorMessage = "Failed to retrieve the OTP from the server.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bot2Door Secure Terminal'),
        backgroundColor: Colors.white,
        elevation: 1.0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.background,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, minHeight: 600),
            child: Card(
              elevation: 12,
              shadowColor: Colors.black.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: _buildContentForState(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Builder Methods ---
  // (No changes from here down)
  // ---

  Widget _buildContentForState() {
    switch (_currentState) {
      case DeliveryFlowState.welcome:
        return _buildWelcomeView(key: const ValueKey('welcome'));
      case DeliveryFlowState.awaitingNotification:
        return _buildWaitingView(
          key: const ValueKey('waiting'),
          icon: Icons.wifi_tethering_rounded,
          color: Theme.of(context).colorScheme.secondary,
          text: "Notifying Homeowner...",
          showCancelButton: true, // Show the cancel button
        );
      case DeliveryFlowState.otpReady:
        return _buildOtpView(key: const ValueKey('otpReady'));
      case DeliveryFlowState.completed:
        return _buildWaitingView(
          key: const ValueKey('completed'),
          icon: Icons.check_circle_rounded,
          color: Colors.green.shade600,
          text: "Delivery Complete!",
          showSpinner: false,
        );
      case DeliveryFlowState.error:
         return _buildErrorView(key: const ValueKey('error'));
    }
  }

  Widget _buildWelcomeView({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        ScaleTransition(
          scale: _scaleAnimation,
          child: Icon(
            Icons.local_shipping_outlined,
            size: 100,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          "Bot2Door",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        const SizedBox(height: 12),
        Text(
          "Ready to accept deliveries.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 60),
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: _startDeliveryProcess,
          label: const Text("Start Delivery"),
        ),
        const Spacer(),
        Text(
          "© 2025 Bot2Door Secure Systems",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildWaitingView({
    required Key key,
    required IconData icon,
    required Color color,
    required String text,
    bool showSpinner = true,
    bool showCancelButton = false, // Add new parameter
  }) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 80, color: color),
        const SizedBox(height: 24),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        if(showSpinner) ...[
          const SizedBox(height: 40),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeWidth: 3,
          ),
        ],
        if (showCancelButton) ...[
          const SizedBox(height: 32),
          TextButton(
            onPressed: _cancelDelivery, // Hook up the cancel method
            child: const Text(
              "Cancel Delivery",
              style: TextStyle(
                fontSize: 16,
                color: Colors.redAccent,
                fontWeight: FontWeight.w600
              ),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildOtpView({required Key key}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.speaker_phone_rounded, size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        const Text(
          "Speaking OTP:",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Text(
          _spokenOtp.replaceAll('...', ' '), // Display OTP with spaces
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
            color: Colors.black87
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView({required Key key}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline_rounded, size: 80, color: Colors.redAccent),
        const SizedBox(height: 24),
        const Text(
          "Connection Error",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
        const SizedBox(height: 12),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => setState(() => _currentState = DeliveryFlowState.welcome),
          child: const Text("Try Again"),
        ),
      ],
    );
  }
}