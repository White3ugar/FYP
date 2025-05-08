import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

class DialogflowService {
  final String projectId = 'fyp1-f09f5';
  final String languageCode = 'en'; // or your preferred language
    final Logger logger = Logger();

  Future<Map<String, dynamic>> detectIntent(String query) async {
    // Log the incoming query
    logger.i("Sending query to Dialogflow: $query");

    // Load service account credentials
    final serviceAccountJson = await rootBundle.loadString('assets/credential/fyp1-f09f5-276ff280519c.json');
    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);

    // Authorize using scopes required by Dialogflow
    final client = await clientViaServiceAccount(
      credentials,
      ['https://www.googleapis.com/auth/cloud-platform'],
    );

    // Generate a unique session ID
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    final url = Uri.parse(
      'https://dialogflow.googleapis.com/v2/projects/$projectId/agent/sessions/$sessionId:detectIntent',
    );

    final response = await client.post(
      url,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'queryInput': {
          'text': {
            'text': query,
            'languageCode': languageCode,
          }
        }
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      logger.i("Dialogflow response: ${json['queryResult']['parameters']}");
      return json['queryResult']['parameters'] ?? {};
    } else {
      logger.e("Dialogflow request failed: ${response.body}");
      throw Exception('Dialogflow request failed: ${response.body}');
    }
  }
}

class AIPage extends StatefulWidget {
  const AIPage({super.key});

  @override
  State<AIPage> createState() => _AIPageState();
}

class _AIPageState extends State<AIPage> {
  final logger = Logger();

  final String _projectId = 'fyp1-f09f5'; 
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;
  final List<({Image? image, String? text, bool fromUser})> _generatedContent = [];

  // Initialize dialogflowService
  final DialogflowService dialogflowService = DialogflowService(); 

  @override
  void initState() {
    super.initState();
    if (_apiKey.isNotEmpty) {
      logger.i("Gemini API Key is set. Features will be enabled.");
    } else {
      logger.i("API Key is missing. Gemini features will be disabled.");
    }
  }

  String? getCurrentUserID() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  String getMonthAbbreviation(DateTime date) {
    const List<String> monthAbbreviations = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return monthAbbreviations[date.month - 1];
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCirc,
      ),
    );
  }

  Future<String> fetchAndSummarizeExpenses(String userID, DateTime startDate, DateTime endDate) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final Map<String, double> categoryTotals = {};
    double total = 0.0;

    // Generate list of months between startDate and endDate
    DateTime monthCursor = DateTime(startDate.year, startDate.month);
    final DateTime endMonth = DateTime(endDate.year, endDate.month);

    while (!monthCursor.isAfter(endMonth)) {
      final String monthName = getMonthAbbreviation(monthCursor);
      final monthDocRef = firestore.collection('expenses').doc(userID).collection('Months').doc(monthName);
      logger.i("Fetching data for userID: $userID, month: $monthName");

      final monthSnapshot = await monthDocRef.get();
      if (!monthSnapshot.exists) {
        logger.w("No data found for month: $monthName");
        monthCursor = DateTime(monthCursor.year, monthCursor.month + 1);
        continue;
      }

      final availableDates = List<String>.from(monthSnapshot.data()?['availableDates'] ?? []);
      logger.i("Available dates in $monthName: $availableDates");

      for (String dateStr in availableDates) {
        final parts = dateStr.split('-');
        if (parts.length != 3) continue;

        final parsedDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );

        if (parsedDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
            parsedDate.isBefore(endDate.add(const Duration(days: 1)))) {
          logger.i("Processing date: $dateStr");
          final dayCollectionRef = monthDocRef.collection(dateStr);
          final dayDocs = await dayCollectionRef.get();

          if (dayDocs.docs.isEmpty) {
            logger.w("No documents found for date: $dateStr");
          }

          for (var doc in dayDocs.docs) {
            final data = doc.data();
            final String category = data['category'] ?? 'Uncategorized';
            final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

            logger.i("Fetched record - Date: $dateStr, Category: $category, Amount: RM${amount.toStringAsFixed(2)}");

            categoryTotals[category] = (categoryTotals[category] ?? 0.0) + amount;
            total += amount;
          }
        }
      }

      // Move to next month
      monthCursor = DateTime(monthCursor.year, monthCursor.month + 1);
    }

    if (categoryTotals.isEmpty) {
      return 'No expense data found for the given period.';
    }

    final buffer = StringBuffer('Expense summary for the period from $startDate to $endDate:\n');
    categoryTotals.forEach((category, amt) {
      buffer.writeln('- $category: RM${amt.toStringAsFixed(2)}');
    });
    buffer.writeln('Total: RM${total.toStringAsFixed(2)}');
    return buffer.toString();
  }

  Future<void> _sendMessage() async {
    if (_textController.text.isEmpty) return;

    final String userPrompt = _textController.text;
    _textController.clear();

    setState(() {
      _loading = true;
      _generatedContent.add((image: null, text: userPrompt, fromUser: true));
    });
    _scrollToBottom();

    try {
      // Load service account credentials
      final serviceAccountJson = await rootBundle.loadString('assets/credential/fyp1-f09f5-e4debf32889d.json');
      final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);

      // Authorize using scopes required by Vertex AI
      final client = await clientViaServiceAccount(
        credentials,
        ['https://www.googleapis.com/auth/cloud-platform'],
      );

      // Setup the API endpoint for Vertex AI
      final String endpoint =
          'https://us-central1-aiplatform.googleapis.com/v1/projects/$_projectId/locations/us-central1/predict:predict';

      // Define the request body (you can adjust the input format for your needs)
      final body = jsonEncode({
        'instances': [
          {'content': userPrompt}  // Modify if Vertex AI requires specific input format
        ]
      });

      // Send the request to Vertex AI
      final response = await client.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        // Log and process the response from Vertex AI
        logger.i("Vertex AI response: $jsonResponse");

        // If there’s a response from the model, process and display the result
        final String text = jsonResponse['predictions'][0] ?? "No response from AI model";
        setState(() {
          _generatedContent.add((image: null, text: text, fromUser: false));
          _loading = false;
        });
        _scrollToBottom();
      } else {
        throw Exception('Vertex AI request failed: ${response.body}');
      }
    } catch (e) {
      logger.e("Error while sending message: $e");
      _showError(e.toString());
      setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini Chatbot'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            Expanded(
              child: _apiKey.isNotEmpty
                ? ListView.builder(
                    controller: _scrollController,
                    itemCount: _generatedContent.length,
                    itemBuilder: (context, index) {
                      final content = _generatedContent[index];
                      return MessageWidget(
                        text: content.text,
                        image: content.image,
                        isFromUser: content.fromUser,
                      );
                    },
                  )
                : const Center(
                    child: Text("API Key not configured. Chat is disabled."),
                  ),
            ),
            if (_loading) const CircularProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 15),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      autofocus: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.all(15),
                        hintText: 'Enter a prompt...',
                        border: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(14),
                          ),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(14),
                          ),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                      onSubmitted: _apiKey.isNotEmpty ? (_) => _sendMessage() : null,
                    ),
                  ),
                  const SizedBox.square(dimension: 15),
                  if (!_loading)
                    IconButton(
                      onPressed: _apiKey.isNotEmpty ? _sendMessage : null,
                      icon: Icon(
                        Icons.send,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  else
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageWidget extends StatelessWidget {
  final String? text;
  final Image? image;
  final bool isFromUser;

  const MessageWidget({
    super.key,
    this.text,
    this.image,
    required this.isFromUser,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: isFromUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image != null) image!,
                if (text != null) Text(text!),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
