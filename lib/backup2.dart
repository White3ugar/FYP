import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

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

  @override
  void initState() {
    super.initState();
    if (_apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
      );
      _chat = _model.startChat();
    } else {
      logger.i("API Key is missing. Gemini features will be disabled.");
    }
  }

  String? getCurrentUserID() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  String getCurrentMonthName() {
    final now = DateTime.now();
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return monthNames[now.month - 1];
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

  Future<String> fetchAndSummarizeExpenses(String userID, String month) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final Map<String, double> categoryTotals = {};
    double total = 0.0;

    final monthDocRef = firestore.collection('expenses').doc(userID).collection('Months').doc(month);

    final monthSnapshot = await monthDocRef.get();
    if (!monthSnapshot.exists) {
      logger.w("No month document found for: $month");
      return 'No expense data found for $month.';
    }

    final availableDates = List<String>.from(monthSnapshot.data()?['availableDates'] ?? []);
    logger.i("Available dates for $month: $availableDates");

    for (String date in availableDates) {
      final dayCollectionRef = monthDocRef.collection(date);
      final dayDocs = await dayCollectionRef.get();

      if (dayDocs.docs.isEmpty) {
        logger.w("No expense documents found for date: $date");
      }

      for (var doc in dayDocs.docs) {
        final data = doc.data();
        final String category = data['category'] ?? 'Uncategorized';
        final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

        logger.i("Fetched record - Date: $date, Category: $category, Amount: RM${amount.toStringAsFixed(2)}");

        categoryTotals[category] = (categoryTotals[category] ?? 0.0) + amount;
        total += amount;
      }
    }

    final buffer = StringBuffer('Expense summary for $month:\n');
    categoryTotals.forEach((category, amt) {
      buffer.writeln('- $category: RM${amt.toStringAsFixed(2)}');
    });
    buffer.writeln('Total: RM${total.toStringAsFixed(2)}');
    return buffer.toString();
  }

  Future<void> _sendMessage() async {
    if (_apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("API Key not configured. Cannot send message."))
      );
      return;
    }

    if (_textController.text.isEmpty) return;

    final String userPrompt = _textController.text;
    _textController.clear();

    setState(() {
      _loading = true;
      _generatedContent.add((image: null, text: userPrompt, fromUser: true));
    });
    _scrollToBottom();

    try {
      String finalPrompt = userPrompt;
      
      // Explicitly instruct to avoid markdown formatting
      finalPrompt = "Please respond without using any Markdown formatting such as **bold**, *italic*, or any other special characters or symbols that are not part of the plain text. The response should only contain regular text without any formatting.";

      // Detect intent for budget recommendation
      if (userPrompt.toLowerCase().contains("budget recommendation")) {
        try {
          finalPrompt = await _buildBudgetRecommendationPrompt(userPrompt);
        } catch (e) {
          _showError(e.toString());
          setState(() => _loading = false);
          return;
        }
      }

      // Add length instruction if not already present
      if (!finalPrompt.toLowerCase().contains("short") &&
          !finalPrompt.toLowerCase().contains("concise") &&
          !finalPrompt.toLowerCase().contains("limit")) {
        finalPrompt = "Please reply concisely in under 20 sentences.\n\n$finalPrompt";
      }

      final response = await _chat.sendMessage(Content.text(finalPrompt));
      final String? text = response.text;

      if (text == null) {
        _showError('No response from API.');
        return;
      } else {
        setState(() {
          _generatedContent.add((image: null, text: text, fromUser: false));
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      _showError(e.toString());
      setState(() => _loading = false);
    }
  }

  Future<String> _buildBudgetRecommendationPrompt(String userPrompt) async {
    final uid = getCurrentUserID();
    final month = getCurrentMonthName();
    
    if (uid == null) {
      throw Exception("User not logged in.");
    }

    final expenseSummary = await fetchAndSummarizeExpenses(uid, month);
    if (expenseSummary.isEmpty) {
      throw Exception("No expense data available for the current month.");
    }

    return "$expenseSummary\n\nBased on this breakdown, please provide a budget recommendation for each category individually, and suggest how much I should allocate to each one next month.";
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
