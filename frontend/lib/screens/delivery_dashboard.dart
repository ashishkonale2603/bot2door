import 'package:flutter/material.dart';
import 'dart:async'; // For Completer
import '../services/api_service.dart'; // Import the API service
import 'package:flutter_tts/flutter_tts.dart'; // Import the TTS package
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

// Simplified states for the new flow
enum DeliveryFlowState {
  welcome,
  greeting,       // "Hello, please state..."
  listening,      // App is actively listening
  processing,     // "Thinking..." while Gemini works
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

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen>
    with SingleTickerProviderStateMixin {
  DeliveryFlowState _currentState = DeliveryFlowState.welcome;
  String _spokenOtp = "";
  String _errorMessage = "";
  Timer? _pollingTimer;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastRecognizedWords = "";

  final ApiService _apiService = ApiService();
  final FlutterTts _flutterTts = FlutterTts();

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

    // Call our new setup functions
    _setupTts();
    _initSpeech();
  }

  // --- NEW: Function to set up the Indian English voice ---
  void _setupTts() async {
    // Wait for TTS to be ready


    // Set default language to Indian English
    _flutterTts.setLanguage("en-IN");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setPitch(1.0);

    try {
      List<dynamic> voices = await _flutterTts.getVoices;
      
      // Look for an "en-IN" female locale
      dynamic indianVoice = voices.firstWhere(
        (voice) =>
            voice['locale'].toLowerCase().contains('en-in') &&
            voice['name'].toLowerCase().contains('female'),
      );

      if (indianVoice != null) {
        print("Setting to Indian voice: $indianVoice");
        await _flutterTts.setVoice(
            {"name": indianVoice['name'], "locale": indianVoice['locale']});
      } else {
        print("No specific Indian (en-IN) female voice found. Using default.");
      }
    } catch (e) {
      print("Could not get or set voices: $e. Using default.");
    }
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (error) => print('STT Error: $error'),
      onStatus: (status) => print('STT Status: $status'),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _animationController.dispose();
    _speechToText.stop();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String text, {required Function onComplete}) async {
    final Completer<void> ttsCompleter = Completer();
    _flutterTts.setCompletionHandler(() {
      if (!ttsCompleter.isCompleted) {
        ttsCompleter.complete();
      }
    });

    await _flutterTts.speak(text);
    await ttsCompleter.future;

    if (mounted) {
      onComplete();
    }
  }

  // Step 1 - Start the single-prompt conversation
  Future<void> _startConversation() async {
    setState(() {
      _currentState = DeliveryFlowState.greeting;
      _lastRecognizedWords = "";
    });

    _speak(
      "Hello, and welcome to Bot2Door. Please state your company and the purpose of your delivery.",
      onComplete: _startListening,
    );
  }

  // Step 2 - Listen for the single, complete phrase
  void _startListening() {
    setState(() => _currentState = DeliveryFlowState.listening);
    _lastRecognizedWords = "";
    _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 15), // Listen for longer
      pauseFor: const Duration(seconds: 4), // Wait 4s for silence
      localeId: "en_IN", // --- CHANGED: Listen for Indian English ---
    );
  }

  // Step 3 - Handle the final speech result
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastRecognizedWords = result.recognizedWords;
    });

    if (result.finalResult) {
      print("Raw text collected: ${result.recognizedWords}");
      _processSpeech(result.recognizedWords);
    }
  }

  // Step 4 - Call the Gemini backend
  Future<void> _processSpeech(String rawText) async {
    setState(() => _currentState = DeliveryFlowState.processing);

    if (rawText.isEmpty) {
      // Handle case where user didn't say anything
      _speak("Sorry, I didn't hear anything. Please try again.", onComplete: () {
        setState(() => _currentState = DeliveryFlowState.welcome);
      });
      return;
    }

    try {
      final extractedData = await _apiService.understandSpeech(rawText);
      final company = extractedData['company_name'];
      final info = extractedData['delivery_info'];

      print("Gemini Extracted: Company=$company, Info=$info");

      if (company == "unknown" || info == "unknown") {
        // Handle if Gemini couldn't figure it out
        _speak(
          "Sorry, I didn't quite catch that. Could you please try again?",
          onComplete: () {
            setState(() => _currentState = DeliveryFlowState.welcome);
          },
        );
      } else {
        // SUCCESS! Now call the original backend process
        _speak(
          "Thank you. Please wait one moment while I notify the homeowner.",
          onComplete: () {
            _startBackendProcess(company, info);
          },
        );
      }
    } catch (e) {
      print("Error processing speech: $e");
      setState(() {
        _currentState = DeliveryFlowState.error;
        _errorMessage = "Sorry, I had trouble understanding. Please try again.";
      });
    }
  }

  // Step 5 - Now accepts arguments
  Future<void> _startBackendProcess(String company, String info) async {
    setState(() {
      _currentState = DeliveryFlowState.awaitingNotification;
      _errorMessage = "";
    });

    try {
      // Pass the Gemini-extracted data to the backend
      await _apiService.startDelivery(company, info);

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
    _pollingTimer?.cancel();
    _speechToText.stop();
    _flutterTts.stop();

    try {
      await _apiService.cancelDelivery();
      setState(() {
        _currentState = DeliveryFlowState.welcome;
      });
    } catch (e) {
      setState(() {
        _currentState = DeliveryFlowState.welcome;
        _errorMessage = "Could not cancel. Resetting.";
      });
    }
  }

  Future<void> _fetchAndSpeakOtp() async {
    try {
      final otp = await _apiService.getSpokenOtp();
      setState(() {
        _currentState = DeliveryFlowState.otpReady;
        _spokenOtp = otp;
      });

      _speak(
        _spokenOtp,
        onComplete: () async {
          if (mounted) {
            setState(() => _currentState = DeliveryFlowState.completed);
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) {
              setState(() => _currentState = DeliveryFlowState.welcome);
            }
          }
        },
      );
    } catch (e) {
      setState(() {
        _currentState = DeliveryFlowState.error;
        _errorMessage = "Failed to retrieve the OTP from the server.";
      });
    }
  }

  // --- UI Builder Methods ---

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
                padding: const EdgeInsets.symmetric(
                    horizontal: 40.0, vertical: 24.0),
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


  Widget _buildContentForState() {
    switch (_currentState) {
      case DeliveryFlowState.welcome:
        return _buildWelcomeView(key: const ValueKey('welcome'));

      case DeliveryFlowState.greeting:
        return _buildWaitingView(
          key: const ValueKey('greeting'),
          icon: Icons.record_voice_over,
          color: Theme.of(context).colorScheme.primary,
          text: "Please answer the question...",
          showSpinner: true,
          showCancelButton: true,
        );

      case DeliveryFlowState.listening:
        return _buildListeningView(
          key: const ValueKey('listen'),
          prompt: "Please state your company and delivery info...",
        );

      case DeliveryFlowState.processing:
        return _buildWaitingView(
          key: const ValueKey('processing'),
          icon: Icons.auto_awesome, // "Magic" icon
          color: Theme.of(context).colorScheme.secondary,
          text: "Processing...",
          showSpinner: true,
          showCancelButton: true,
        );

      case DeliveryFlowState.awaitingNotification:
        return _buildWaitingView(
          key: const ValueKey('waiting'),
          icon: Icons.wifi_tethering_rounded,
          color: Theme.of(context).colorScheme.secondary,
          text: "Notifying Homeowner...",
          showCancelButton: true,
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
    return _buildWelcomeView(key: const ValueKey('default')); // Fallback
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
          style: TextStyle(
              fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 1.5),
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
          onPressed: _speechEnabled ? _startConversation : null,
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
    bool showCancelButton = false,
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
        if (showSpinner) ...[
          const SizedBox(height: 40),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeWidth: 3,
          ),
        ],
        if (showCancelButton) ...[
          const SizedBox(height: 32),
          TextButton(
            onPressed: _cancelDelivery,
            child: const Text(
              "Cancel Delivery",
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildListeningView({required Key key, required String prompt}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.mic,
            size: 80, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 24),
        Text(
          prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 40),
        const Text(
          "Listening...",
          style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
        Container(
          height: 100,
          child: Text(
            _lastRecognizedWords,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: _cancelDelivery,
          child: const Text(
            "Cancel Delivery",
            style: TextStyle(
                fontSize: 16,
                color: Colors.redAccent,
                fontWeight: FontWeight.w600),
          ),
        )
      ],
    );
  }

  Widget _buildOtpView({required Key key}) {
     return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.speaker_phone_rounded,
            size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        const Text(
          "Speaking OTP:",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Text(
          _spokenOtp.replaceAll('...', ' '),
          style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              color: Colors.black87),
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
        const Icon(Icons.error_outline_rounded,
            size: 80, color: Colors.redAccent),
        const SizedBox(height: 24),
        const Text(
          "Connection Error",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent),
        ),
        const SizedBox(height: 12),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () =>
              setState(() => _currentState = DeliveryFlowState.welcome),
          child: const Text("Try Again"),
        ),
      ],
    );
  }
}