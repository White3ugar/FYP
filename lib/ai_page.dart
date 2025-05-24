import 'package:flutter/material.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'expenseRecord_page.dart';
import 'budgeting_page.dart';
import 'home_page.dart';
import 'dataVisual_page.dart';


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
  late final GenerativeModel _model;
  late final ChatSession _chat;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;
  final List<({Image? image, String? text, bool fromUser})> _generatedContent = [];

  // Initialize dialogflowService
  final DialogflowService dialogflowService = DialogflowService(); 

  @override
  void initState() {
    super.initState();

    _model = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash',
      systemInstruction: Content.text(
        "You are a friendly and energetic financial assistant named Sparx. If user asks something not related to finance, "
        "politely inform them that you are not able to assist with that. "
        "Provide concise, clear, and engaging responses. "
        "Avoid using the '*' symbol. "
        "Start directly with the answer—do not use phrases like 'Based on...'. "
        "Include specific values for each expense category when giving reviews or recommendations. "
        "Keep responses under 12 sentences."
      ),
    );
    _chat = _model.startChat();
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
      logger.i("User prompt: $userPrompt");

      String finalPrompt = userPrompt;
      final dialogflowResponse = await dialogflowService.detectIntent(userPrompt);

      final date = dialogflowResponse['date'] ?? '';
      final datePeriod = dialogflowResponse['date-period'] ?? {};

      DateTime? startDate;
      DateTime? endDate;

      if (datePeriod.isNotEmpty) {
        final startDateStr = datePeriod['startDate'];
        final endDateStr = datePeriod['endDate'];
        startDate = DateTime.parse(startDateStr);
        endDate = DateTime.parse(endDateStr);
        finalPrompt = "$finalPrompt from ${startDate.toLocal()} to ${endDate.toLocal()}";
      } else if (date.isNotEmpty) {
        final specificDate = DateTime.parse(date);
        startDate = specificDate;
        endDate = specificDate;
        finalPrompt = "$finalPrompt for ${startDate.toLocal()}";
      }

      if (startDate != null && endDate != null) {
        final uid = getCurrentUserID();
        if (uid == null) throw Exception("User not logged in.");

        final summary = await fetchAndSummarizeExpenses(uid, startDate, endDate);

        if (summary.isEmpty || summary.contains('No expense data')) {
          finalPrompt = "Explain in friendly: No record found in this date period.\n\n$userPrompt";
        } else {
          finalPrompt = "$summary\n\n$userPrompt";
        }
      }

      logger.i("Final prompt: $finalPrompt");
      final response = await _chat.sendMessage(Content.text(finalPrompt));
      final String? text = response.text;

      if (text == null) {
        _showError('No response from Gemini model.');
        return;
      } else {
        setState(() {
          _generatedContent.add((image: null, text: text, fromUser: false));
          _loading = false;
        });
        _scrollToBottom();
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
    double screenWidth = MediaQuery.of(context).size.width;
    double iconSize = screenWidth * 0.08;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat with Sparx!'),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(255, 165, 35, 226),
            ),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
                (route) => false,
              );
            },
          ),
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
                          hintText: 'How can I help you finance better?',
                          border: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        onSubmitted: _apiKey.isNotEmpty && !_loading ? (_) => _sendMessage() : null,
                      ),
                    ),
                    const SizedBox.square(dimension: 15),
                    IconButton(
                      onPressed: _apiKey.isNotEmpty && !_loading ? _sendMessage : null,
                      icon: Icon(
                        Icons.send,
                        color: _loading ? Colors.grey : const Color.fromARGB(255, 165, 35, 226),
                      ),
                    ),
                  ],
                )
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomAppBar(context, iconSize),
      ),
    );
  }

  Widget _buildBottomAppBar(BuildContext context, double iconSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double iconSpacing = screenWidth * 0.14;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomAppBar(
        height: 100,
        elevation: 0,
        color: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildNavIconWithCaption(context, "assets/icon/record-book.png", "Record", iconSize, const ExpenseRecordPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/budget.png", "Budget", iconSize, const BudgetPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/dataVisual.png", "Graphs", iconSize, const DataVisualPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/chatbot.png", "AI", iconSize, const AIPage(), textColor: Colors.deepPurple),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavIconWithCaption(
    BuildContext context,
    String assetPath,
    String caption,
    double size,
    Widget page, {
    Color textColor = Colors.grey
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => page,
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: TextStyle(
            fontSize: 13,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

// MessageWidget is a simple widget to display messages in the chat (Chat bubble)
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
                  ? const Color.fromARGB(255, 165, 35, 226)
                  : const Color.fromARGB(255, 239, 179, 236),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image != null) image!,
                if (text != null)
                  Text(
                    text!,
                    style: TextStyle(
                      color: isFromUser ? Colors.white : Colors.black,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
